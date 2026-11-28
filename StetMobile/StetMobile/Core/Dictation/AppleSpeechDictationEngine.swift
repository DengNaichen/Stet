@preconcurrency import AVFoundation
import Foundation
import Speech
import StetCore

@MainActor
final class AppleSpeechDictationEngine: @MainActor ASREngine, MobileASREngineFailureReporting {
    let name = "Apple Speech"
    let resultStream: AsyncStream<ASRResult>
    let failureStream: AsyncStream<MobileASREngineFailure>
    var onVolumeUpdate: ((Float) -> Void)?

    private let settingsStore: SpeechRecognitionSettingsStore
    private let dictionaryModel: DictionaryModel
    private let audioCapture: any ASRAudioCapturing
    private let resultContinuation: AsyncStream<ASRResult>.Continuation
    private let failureContinuation: AsyncStream<MobileASREngineFailure>.Continuation

    private var recording: Recording?
    private var isStarting = false
    private var startupCancelled = false
    private var isTornDown = false

    init(
        settingsStore: SpeechRecognitionSettingsStore,
        dictionaryModel: DictionaryModel = DictionaryModel(),
        audioCapture: (any ASRAudioCapturing)? = nil
    ) {
        self.settingsStore = settingsStore
        self.dictionaryModel = dictionaryModel
        self.audioCapture = audioCapture ?? PersistentASRAudioCapture(strategy: .builtInPreferred)
        (resultStream, resultContinuation) = AsyncStream.makeStream()
        (failureStream, failureContinuation) = AsyncStream.makeStream()
    }

    func prepare() async throws {
        try checkOpen()
        _ = try await settingsStore.prepareLocale()
        try checkOpen()
        try await audioCapture.prepare()
    }

    func start(sessionId: String) async throws {
        try checkOpen()
        guard !isStarting, recording?.isStopping != false else {
            throw ASRAudioCaptureError.consumerAlreadyActive
        }
        // The coordinator can start a new session after cancelling the previous one.
        discardRecording()
        isStarting = true
        startupCancelled = false
        defer { isStarting = false }

        let target = try await settingsStore.prepareTarget()
        let activeTranscriber: ActiveTranscriber
        let modules: [any SpeechModule]
        switch target.backend {
        case .speechTranscriber:
            let transcriber = SpeechTranscriber(locale: target.locale, preset: .progressiveTranscription)
            activeTranscriber = .speech(transcriber)
            modules = [transcriber]
        case .dictationTranscriber:
            let transcriber = DictationTranscriber(locale: target.locale, preset: .progressiveLongDictation)
            activeTranscriber = .dictation(transcriber)
            modules = [transcriber]
        }

        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: modules) else {
            throw EngineError.audioFormatUnavailable
        }
        let conversion = try AudioConversion(outputFormat: format)
        let analyzer = SpeechAnalyzer(modules: modules)
        let inputs = AsyncStream<AnalyzerInput>.makeStream(bufferingPolicy: .bufferingOldest(128))
        let frames = AsyncThrowingStream<ASRAudioFrame, any Error>.makeStream(bufferingPolicy: .bufferingOldest(128))

        do {
            if case .dictation = activeTranscriber, dictionaryModel.loadIsEnabled() {
                let hotwords = Array(dictionaryModel.loadEntries().prefix(100))
                if !hotwords.isEmpty {
                    let context = AnalysisContext()
                    context.contextualStrings[.general] = hotwords
                    try await analyzer.setContext(context)
                }
            }

            try await analyzer.prepareToAnalyze(in: format)
            try await analyzer.start(inputSequence: inputs.stream)
            try checkStartup()
            let startedAt = ProcessInfo.processInfo.systemUptime
            try await audioCapture.start { [continuation = frames.continuation] result in
                switch result {
                case .success(let frame):
                    if case .dropped = continuation.yield(frame) {
                        continuation.finish(throwing: EngineError.audioBacklog)
                    }
                case .failure(let error):
                    continuation.finish(throwing: error)
                }
            }
            try checkStartup()

            let token = UUID()
            let results = consumeResults(activeTranscriber, sessionId: sessionId, token: token)
            let drain = Task { [weak self] in
                do {
                    var sampleCount = 0
                    for try await frame in frames.stream {
                        try Task.checkCancellation()
                        guard !frame.samples.isEmpty else { continue }
                        self?.onVolumeUpdate?(frame.level)
                        sampleCount += frame.samples.count
                        try Self.yield(conversion.convert(frame), to: inputs.continuation)
                    }
                    try Task.checkCancellation()

                    let text: String
                    if sampleCount > 0 {
                        try conversion.flush { try Self.yield($0, to: inputs.continuation) }
                        inputs.continuation.finish()
                        try await analyzer.finalizeAndFinishThroughEndOfInput()
                        text = try await results.value
                    } else {
                        inputs.continuation.finish()
                        results.cancel()
                        await analyzer.cancelAndFinishNow()
                        text = ""
                    }

                    let duration = Double(sampleCount) / ASRAudioFrame.sampleRate
                    let wallDuration = ProcessInfo.processInfo.systemUptime - startedAt
                    self?.complete(
                        token: token,
                        text: text,
                        metrics: ASRMetrics(
                            audioDuration: duration,
                            cpuDuration: 0,
                            wallDuration: wallDuration,
                            rtf: duration > 0 ? wallDuration / duration : 0
                        )
                    )
                } catch {
                    guard !Task.isCancelled else { return }
                    self?.failRecording(token: token, error: error)
                }
            }
            recording = Recording(
                id: sessionId,
                token: token,
                analyzer: analyzer,
                frames: frames.continuation,
                inputs: inputs.continuation,
                results: results,
                drain: drain
            )
        } catch {
            audioCapture.stop()
            frames.continuation.finish()
            inputs.continuation.finish()
            await analyzer.cancelAndFinishNow()
            throw error
        }
    }

    func stop() {
        if isStarting { startupCancelled = true }
        guard let recording, !recording.isStopping else { return }
        self.recording?.isStopping = true
        audioCapture.stop()
        // The drain task flushes queued frames and closes analyzer input in order.
        recording.frames.finish()
    }

    func resetAudio() async throws {
        try checkOpen()
        if isStarting { startupCancelled = true }
        if let recording {
            failRecording(token: recording.token, error: EngineError.audioReset)
        }
        try await audioCapture.reset()
    }

    func suspendAudio() {
        guard !isTornDown, !isStarting, recording == nil else { return }
        audioCapture.teardown()
    }

    func teardown() {
        guard !isTornDown else { return }
        isTornDown = true
        discardRecording()
        audioCapture.teardown()
        resultContinuation.finish()
        failureContinuation.finish()
    }

    private func checkOpen() throws {
        try Task.checkCancellation()
        guard !isTornDown else { throw CancellationError() }
    }

    private func checkStartup() throws {
        try checkOpen()
        guard !startupCancelled else { throw CancellationError() }
    }

    private enum ActiveTranscriber {
        case speech(SpeechTranscriber)
        case dictation(DictationTranscriber)
    }

    private func consumeResults(
        _ transcriber: ActiveTranscriber,
        sessionId: String,
        token: UUID
    ) -> Task<String, any Error> {
        Task { [weak self] in
            var finalizedText = ""
            do {
                switch transcriber {
                case .speech(let speechTranscriber):
                    for try await result in speechTranscriber.results {
                        try Task.checkCancellation()
                        guard let self, self.recording?.token == token else { throw CancellationError() }
                        let text = String(result.text.characters)
                        if result.isFinal {
                            finalizedText += text
                        }
                        self.resultContinuation.yield(
                            ASRResult(
                                sessionId: sessionId,
                                text: result.isFinal ? finalizedText : finalizedText + text,
                                isFinal: false
                            )
                        )
                    }
                case .dictation(let dictationTranscriber):
                    for try await result in dictationTranscriber.results {
                        try Task.checkCancellation()
                        guard let self, self.recording?.token == token else { throw CancellationError() }
                        let text = String(result.text.characters)
                        if result.isFinal {
                            finalizedText += text
                        }
                        self.resultContinuation.yield(
                            ASRResult(
                                sessionId: sessionId,
                                text: result.isFinal ? finalizedText : finalizedText + text,
                                isFinal: false
                            )
                        )
                    }
                }
                if self?.recording?.isStopping == false, !Task.isCancelled {
                    throw EngineError.analysisEnded
                }
                return finalizedText.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                if !Task.isCancelled {
                    self?.failRecording(token: token, error: error)
                }
                throw error
            }
        }
    }

    private func complete(token: UUID, text: String, metrics: ASRMetrics) {
        guard let recording, recording.token == token else { return }
        self.recording = nil
        resultContinuation.yield(ASRResult(sessionId: recording.id, text: text, isFinal: true, metrics: metrics))
    }

    private func failRecording(token: UUID, error: any Error) {
        guard let recording, recording.token == token else { return }
        discardRecording()
        failureContinuation.yield(MobileASREngineFailure(sessionId: recording.id, message: error.localizedDescription))
    }

    private func discardRecording() {
        guard let recording else { return }
        self.recording = nil
        audioCapture.stop()
        recording.results.cancel()
        recording.drain.cancel()
        recording.frames.finish()
        recording.inputs.finish()
        Task { await recording.analyzer.cancelAndFinishNow() }
    }

    private static func yield(
        _ buffer: AVAudioPCMBuffer,
        to continuation: AsyncStream<AnalyzerInput>.Continuation
    ) throws {
        guard buffer.frameLength > 0 else { return }
        switch continuation.yield(AnalyzerInput(buffer: buffer)) {
        case .enqueued: break
        case .dropped: throw EngineError.audioBacklog
        case .terminated: throw CancellationError()
        @unknown default: throw EngineError.audioBacklog
        }
    }

    private struct Recording {
        let id: String
        let token: UUID
        let analyzer: SpeechAnalyzer
        let frames: AsyncThrowingStream<ASRAudioFrame, any Error>.Continuation
        let inputs: AsyncStream<AnalyzerInput>.Continuation
        let results: Task<String, any Error>
        let drain: Task<Void, Never>
        var isStopping = false
    }

    private enum EngineError: LocalizedError {
        case audioFormatUnavailable
        case audioConversionFailed
        case audioBacklog
        case audioReset
        case analysisEnded

        var errorDescription: String? {
            switch self {
            case .audioFormatUnavailable: "Apple Speech could not find a compatible audio format."
            case .audioConversionFailed: "Microphone audio could not be converted for Apple Speech."
            case .audioBacklog: "Apple Speech could not keep up with the microphone."
            case .audioReset: "Audio services were reset. Please try again."
            case .analysisEnded: "Apple Speech ended before the recording was stopped."
            }
        }
    }

    private struct AudioConversion {
        let sourceFormat: AVAudioFormat
        let converter: AVAudioConverter?

        init(outputFormat: AVAudioFormat) throws {
            guard
                let sourceFormat = AVAudioFormat(
                    commonFormat: .pcmFormatFloat32,
                    sampleRate: ASRAudioFrame.sampleRate,
                    channels: 1,
                    interleaved: false
                )
            else { throw EngineError.audioFormatUnavailable }
            self.sourceFormat = sourceFormat
            if sourceFormat == outputFormat {
                converter = nil
            } else {
                guard let converter = AVAudioConverter(from: sourceFormat, to: outputFormat) else {
                    throw EngineError.audioFormatUnavailable
                }
                self.converter = converter
            }
        }

        func convert(_ frame: ASRAudioFrame) throws -> AVAudioPCMBuffer {
            let frameCount = AVAudioFrameCount(frame.samples.count)
            guard let source = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: frameCount),
                let channel = source.floatChannelData?[0]
            else { throw EngineError.audioConversionFailed }
            frame.samples.withUnsafeBufferPointer { samples in
                if let address = samples.baseAddress {
                    channel.update(from: address, count: samples.count)
                }
            }
            source.frameLength = frameCount

            guard let converter else { return source }
            let ratio = converter.outputFormat.sampleRate / sourceFormat.sampleRate
            let capacity = AVAudioFrameCount(ceil(Double(frameCount) * ratio)) + 1
            let output = try makeOutput(for: converter, capacity: capacity)
            var suppliedInput = false
            var error: NSError?
            let status = converter.convert(to: output, error: &error) { _, inputStatus in
                if suppliedInput {
                    inputStatus.pointee = .noDataNow
                    return nil
                }
                suppliedInput = true
                inputStatus.pointee = .haveData
                return source
            }
            guard status != .error else { throw error ?? EngineError.audioConversionFailed }
            return output
        }

        func flush(_ consume: (AVAudioPCMBuffer) throws -> Void) throws {
            guard let converter else { return }
            while true {
                let output = try makeOutput(for: converter, capacity: 4096)
                var error: NSError?
                let status = converter.convert(to: output, error: &error) { _, inputStatus in
                    inputStatus.pointee = .endOfStream
                    return nil
                }
                guard status != .error else { throw error ?? EngineError.audioConversionFailed }
                try consume(output)
                guard status == .haveData, output.frameLength > 0 else { return }
            }
        }

        private func makeOutput(for converter: AVAudioConverter, capacity: AVAudioFrameCount) throws -> AVAudioPCMBuffer
        {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: capacity) else {
                throw EngineError.audioConversionFailed
            }
            return buffer
        }
    }
}
