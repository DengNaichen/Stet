@preconcurrency import AVFoundation
import Foundation
import os
import whisper

final class WhisperASREngine: ASREngine {
    let name = "Whisper large-v3-turbo"

    let resultStream: AsyncStream<ASRResult>
    private let continuation: AsyncStream<ASRResult>.Continuation
    private let modelManager: WhisperModelManager
    private let runtime = WhisperRuntime()
    private let lock = NSLock()
    private let outputFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
    )
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.openwhispr.StetMobile",
        category: "WhisperLifecycle"
    )

    private var audioEngine: AVAudioEngine?
    private var converter: AVAudioConverter?
    private var activeSessionId: String?
    private var recordedSamples: [Float] = []
    private var inferenceTask: Task<Void, Never>?

    var onVolumeUpdate: ((Float) -> Void)?

    init(modelManager: WhisperModelManager) {
        self.modelManager = modelManager
        (resultStream, continuation) = AsyncStream.makeStream()
    }

    func prepare() async throws {
        try await configureAudioSessionAndEngine()
    }

    func start(sessionId: String) async throws {
        if audioEngine == nil {
            try await prepare()
        }

        let urls = try await modelManager.resolveModelURLs(for: WhisperModelManager.modelName)
        guard let modelURL = urls[WhisperModelManager.modelKey] else {
            throw WhisperModelManagerError.modelNotDownloaded
        }

        let loadStartedAt = ProcessInfo.processInfo.systemUptime
        try await runtime.initializeModel(at: modelURL)
        logger.info(
            "event=model_loaded backend=cpu duration_ms=\(Self.elapsedMilliseconds(since: loadStartedAt), privacy: .public)"
        )

        #if os(iOS)
            try await Self.activateAudioSession()
        #endif
        if let audioEngine, !audioEngine.isRunning {
            try audioEngine.start()
        }

        lock.withLock {
            activeSessionId = sessionId
            recordedSamples.removeAll(keepingCapacity: true)
        }
    }

    func stop() {
        let recording = lock.withLock { () -> (sessionId: String, samples: [Float])? in
            guard let activeSessionId else { return nil }
            let recording = (activeSessionId, recordedSamples)
            self.activeSessionId = nil
            recordedSamples.removeAll(keepingCapacity: false)
            return recording
        }
        guard let recording else { return }

        let runtime = runtime
        let continuation = continuation
        let logger = logger
        inferenceTask = Task { @concurrent in
            let startedAt = ProcessInfo.processInfo.systemUptime
            let text: String
            let succeeded: Bool
            do {
                text = try await runtime.transcribe(samples: recording.samples)
                succeeded = true
            } catch {
                logger.error("event=transcription_failed error=\(error.localizedDescription, privacy: .public)")
                text = ""
                succeeded = false
            }

            let wallDuration = ProcessInfo.processInfo.systemUptime - startedAt
            let audioDuration = Double(recording.samples.count) / 16_000
            let rtf = audioDuration > 0 ? wallDuration / audioDuration : 0
            await runtime.releaseResources()

            let result = await MainActor.run {
                ASRResult(
                    sessionId: recording.sessionId,
                    text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                    isFinal: true,
                    metrics: ASRMetrics(
                        audioDuration: audioDuration,
                        cpuDuration: wallDuration,
                        wallDuration: wallDuration,
                        rtf: rtf
                    )
                )
            }
            continuation.yield(result)
            if succeeded {
                logger.info(
                    "event=transcription_completed audio_seconds=\(audioDuration, privacy: .public) wall_seconds=\(wallDuration, privacy: .public) rtf=\(rtf, privacy: .public)"
                )
            }
        }
    }

    func resetAudio() async throws {
        let previousEngine = lock.withLock { () -> AVAudioEngine? in
            let previousEngine = audioEngine
            audioEngine = nil
            converter = nil
            activeSessionId = nil
            recordedSamples.removeAll(keepingCapacity: false)
            return previousEngine
        }
        previousEngine?.stop()
        previousEngine?.inputNode.removeTap(onBus: 0)
        try await configureAudioSessionAndEngine()
    }

    func teardown() {
        inferenceTask?.cancel()
        inferenceTask = nil
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        converter = nil
        activeSessionId = nil
        recordedSamples.removeAll(keepingCapacity: false)
        continuation.finish()

        let runtime = runtime
        Task { @concurrent in
            await runtime.releaseResources()
        }
    }

    private func configureAudioSessionAndEngine() async throws {
        #if os(iOS)
            try await Self.configureAudioSession()
        #endif

        try configureAudioEngine()
    }

    private func configureAudioEngine() throws {
        guard audioEngine == nil, outputFormat != nil else { return }

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.channelCount > 0 else {
            throw WhisperASREngineError.audioInputUnavailable
        }

        audioEngine = engine
        converter = nil
        input.installTap(onBus: 0, bufferSize: 4096, format: nil) { [weak self] buffer, _ in
            self?.handleInputBuffer(buffer)
        }
        engine.prepare()
        try engine.start()
    }

    private func handleInputBuffer(_ buffer: AVAudioPCMBuffer) {
        let sessionId = lock.withLock { activeSessionId }
        guard let sessionId,
            buffer.format.sampleRate > 0,
            buffer.format.channelCount > 0,
            let outputFormat,
            let converter = converter(for: buffer.format, outputFormat: outputFormat)
        else { return }

        var consumed = false
        let inputBlock: AVAudioConverterInputBlock = { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }

        let frameCapacity =
            AVAudioFrameCount(Double(buffer.frameLength) * outputFormat.sampleRate / buffer.format.sampleRate) + 1
        guard let converted = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: frameCapacity) else { return }

        var conversionError: NSError?
        let status = converter.convert(to: converted, error: &conversionError, withInputFrom: inputBlock)
        guard status != .error,
            conversionError == nil,
            let channelData = converted.floatChannelData
        else { return }

        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: Int(converted.frameLength)))
        guard !samples.isEmpty else { return }

        let sumOfSquares = samples.reduce(0) { $0 + $1 * $1 }
        let level = min(sqrt(sumOfSquares / Float(samples.count)) * 15, 1)
        let accepted = lock.withLock { () -> Bool in
            guard activeSessionId == sessionId else { return false }
            recordedSamples.append(contentsOf: samples)
            return true
        }
        if accepted {
            onVolumeUpdate?(level)
        }
    }

    private func converter(for inputFormat: AVAudioFormat, outputFormat: AVAudioFormat) -> AVAudioConverter? {
        lock.withLock {
            if let converter,
                Self.formatsMatch(converter.inputFormat, inputFormat)
            {
                return converter
            }

            let newConverter = AVAudioConverter(from: inputFormat, to: outputFormat)
            converter = newConverter
            return newConverter
        }
    }

    private nonisolated static func formatsMatch(_ lhs: AVAudioFormat, _ rhs: AVAudioFormat) -> Bool {
        lhs.sampleRate == rhs.sampleRate
            && lhs.channelCount == rhs.channelCount
            && lhs.commonFormat == rhs.commonFormat
            && lhs.isInterleaved == rhs.isInterleaved
    }

    private nonisolated static func elapsedMilliseconds(since start: TimeInterval) -> String {
        String(format: "%.1f", (ProcessInfo.processInfo.systemUptime - start) * 1_000)
    }

    #if os(iOS)
        private nonisolated static func configureAudioSession() async throws {
            try await Task { @concurrent in
                let session = AVAudioSession.sharedInstance()
                var options: AVAudioSession.CategoryOptions = [
                    .mixWithOthers,
                    .allowBluetoothHFP,
                ]
                if #available(iOS 26.0, *) {
                    options.insert(.bluetoothHighQualityRecording)
                }

                try session.setCategory(.playAndRecord, mode: .default, options: options)
                if #available(iOS 27.0, *) {
                    let activated = try await session.activate(options: [])
                    guard activated else {
                        throw WhisperASREngineError.audioSessionActivationFailed
                    }
                } else {
                    try session.setActive(true)
                }
            }.value
        }

        private nonisolated static func activateAudioSession() async throws {
            try await Task { @concurrent in
                let session = AVAudioSession.sharedInstance()
                if #available(iOS 27.0, *) {
                    let activated = try await session.activate(options: [])
                    guard activated else {
                        throw WhisperASREngineError.audioSessionActivationFailed
                    }
                } else {
                    try session.setActive(true)
                }
            }.value
        }
    #endif
}

private enum WhisperASREngineError: LocalizedError {
    case audioInputUnavailable
    case audioSessionActivationFailed
    case modelLoadFailed
    case transcriptionFailed

    var errorDescription: String? {
        switch self {
        case .audioInputUnavailable:
            return "The microphone input is unavailable."
        case .audioSessionActivationFailed:
            return "The audio session could not be activated."
        case .modelLoadFailed:
            return "Whisper large-v3-turbo could not be loaded on this device."
        case .transcriptionFailed:
            return "Whisper could not transcribe this recording."
        }
    }
}

private actor WhisperRuntime {
    private var context: OpaquePointer?

    deinit {
        if let context {
            whisper_free(context)
        }
    }

    func initializeModel(at modelURL: URL) throws {
        guard context == nil else { return }

        var parameters = whisper_context_default_params()
        parameters.use_gpu = false
        parameters.flash_attn = false

        guard let loadedContext = whisper_init_from_file_with_params(modelURL.path, parameters) else {
            throw WhisperASREngineError.modelLoadFailed
        }
        context = loadedContext
    }

    func transcribe(samples: [Float]) throws -> String {
        guard let context else {
            throw WhisperASREngineError.modelLoadFailed
        }
        guard !samples.isEmpty else { return "" }

        var parameters = whisper_full_default_params(WHISPER_SAMPLING_BEAM_SEARCH)
        parameters.print_realtime = false
        parameters.print_progress = false
        parameters.print_timestamps = false
        parameters.print_special = false
        parameters.translate = false
        parameters.no_context = true
        parameters.temperature = 0
        parameters.n_threads = Int32(max(1, min(4, ProcessInfo.processInfo.processorCount / 2)))
        parameters.beam_search.beam_size = 5
        parameters.language = nil

        whisper_reset_timings(context)
        let result = samples.withUnsafeBufferPointer { buffer in
            whisper_full(context, parameters, buffer.baseAddress, Int32(buffer.count))
        }
        guard result == 0 else {
            throw WhisperASREngineError.transcriptionFailed
        }

        var transcript = ""
        for index in 0..<whisper_full_n_segments(context) {
            transcript += String(cString: whisper_full_get_segment_text(context, index))
        }
        return transcript
    }

    func releaseResources() {
        guard let context else { return }
        whisper_free(context)
        self.context = nil
    }
}
