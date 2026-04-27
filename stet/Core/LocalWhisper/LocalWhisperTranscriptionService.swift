@preconcurrency import AVFoundation
import Foundation
import os

protocol LocalWhisperEngine: Sendable {
    func prewarm() async throws
    func transcribe(
        samples: [Float],
        languageCode: String?,
        prompt: String?
    ) async throws -> TranscriptionResult
    func releaseResources() async
}

enum LocalWhisperEngineFactory {
    nonisolated static var isRuntimeAvailable: Bool {
        #if canImport(whisper)
            true
        #else
            false
        #endif
    }

    nonisolated static func makeEngine(modelURL: URL) throws -> any LocalWhisperEngine {
        #if canImport(whisper)
            return WhisperCppLocalWhisperEngine(modelURL: modelURL)
        #else
            throw LocalWhisperError.runtimeUnavailable
        #endif
    }
}

final class LocalWhisperTranscriptionService: AudioFileTranscriptionService, @unchecked Sendable {
    private let modelURL: URL
    private let engineFactory: @Sendable (URL) throws -> any LocalWhisperEngine
    private let contextManagerProvider: @MainActor @Sendable () -> LocalWhisperContextManager
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.openwhispr.Stet", category: "LocalWhisper")

    init(
        modelManager: LocalWhisperModelManager,
        engineFactory: @escaping @Sendable (URL) throws -> any LocalWhisperEngine = {
            try LocalWhisperEngineFactory.makeEngine(modelURL: $0)
        },
        contextManagerProvider: (@MainActor @Sendable () -> LocalWhisperContextManager)? = nil
    ) throws {
        self.modelURL = try modelManager.resolvedModelURL()
        self.engineFactory = engineFactory
        self.contextManagerProvider = contextManagerProvider ?? { LocalWhisperContextManager.shared }
    }

    /// Loads the model into the shared `LocalWhisperContextManager` if nothing
    /// is loaded. Mirrors `VoiceInkEngine` kicking `whisperModelManager.loadModel`
    /// when a recording starts so the model is hot by the time `transcribe` runs.
    func prewarm() async throws {
        let manager = await contextManagerProvider()
        let factory = engineFactory
        let modelURL = self.modelURL
        try await manager.loadModel(modelURL: modelURL) { url in
            try factory(url)
        }
    }

    func transcribe(
        audioFileAt fileURL: URL,
        languageCode: String?,
        prompt: String?,
        audioDurationSeconds: TimeInterval?
    ) async throws -> TranscriptionResult {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw OpenAIError.fileNotFound(fileURL)
        }

        let startedAt = ProcessInfo.processInfo.systemUptime
        let samplePreparationStartedAt = startedAt
        let samples: [Float]
        do {
            samples = try Self.readSamples(from: fileURL)
        } catch {
            logger.error("Failed to prepare audio for Local Whisper: \(error.localizedDescription, privacy: .public)")
            throw LocalWhisperError.audioPreparationFailed
        }
        let samplePreparationMs = Self.elapsedMilliseconds(since: samplePreparationStartedAt)

        let manager = await contextManagerProvider()
        let reusedEngine = await manager.engineIfLoaded(matching: modelURL)

        let engine: any LocalWhisperEngine
        let isTransient: Bool
        if let reusedEngine {
            engine = reusedEngine
            isTransient = false
        } else {
            let newEngine = try engineFactory(modelURL)
            try await newEngine.prewarm()
            engine = newEngine
            isTransient = true
        }

        let inferenceStartedAt = ProcessInfo.processInfo.systemUptime
        let result: TranscriptionResult
        do {
            result = try await engine.transcribe(
                samples: samples,
                languageCode: languageCode,
                prompt: prompt
            )
        } catch {
            if isTransient {
                await engine.releaseResources()
            }
            AppLogger.error(
                "LocalWhisper failed audioDurationSeconds=\(Self.formatOptionalDurationSeconds(audioDurationSeconds)) samplePreparationMs=\(Self.formatMilliseconds(samplePreparationMs)) inferenceMs=\(Self.formatMilliseconds(Self.elapsedMilliseconds(since: inferenceStartedAt))) languageCode=\(languageCode ?? "auto") promptChars=\(prompt?.count ?? 0) error=\(error.localizedDescription)",
                category: .perfTrace
            )
            throw error
        }
        let inferenceMs = Self.elapsedMilliseconds(since: inferenceStartedAt)
        let totalMs = Self.elapsedMilliseconds(since: startedAt)

        if isTransient {
            await engine.releaseResources()
        }

        let transcript = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else {
            throw SpeechServiceError.emptyTranscription
        }

        AppLogger.info(
            "LocalWhisper completed audioDurationSeconds=\(Self.formatOptionalDurationSeconds(audioDurationSeconds)) sampleCount=\(samples.count) samplePreparationMs=\(Self.formatMilliseconds(samplePreparationMs)) inferenceMs=\(Self.formatMilliseconds(inferenceMs)) totalMs=\(Self.formatMilliseconds(totalMs)) textChars=\(transcript.count) languageCode=\(result.languageCode ?? languageCode ?? "auto") promptChars=\(prompt?.count ?? 0) reusedLoadedContext=\(!isTransient)",
            category: .perfTrace
        )

        return .init(text: transcript, languageCode: result.languageCode)
    }

    private nonisolated static func elapsedMilliseconds(since start: TimeInterval) -> Double {
        (ProcessInfo.processInfo.systemUptime - start) * 1_000
    }

    private nonisolated static func formatMilliseconds(_ duration: Double) -> String {
        String(format: "%.1f", duration)
    }

    private nonisolated static func formatOptionalDurationSeconds(_ duration: TimeInterval?) -> String {
        guard let duration, duration.isFinite, duration >= 0 else {
            return "unknown"
        }

        return String(format: "%.3f", duration)
    }

    private static func readSamples(from fileURL: URL) throws -> [Float] {
        let inputFile = try AVAudioFile(forReading: fileURL)
        let inputFormat = inputFile.processingFormat
        let inputFrameCount = AVAudioFrameCount(inputFile.length)

        guard
            let inputBuffer = AVAudioPCMBuffer(
                pcmFormat: inputFormat,
                frameCapacity: inputFrameCount
            )
        else {
            throw LocalWhisperError.audioPreparationFailed
        }

        try inputFile.read(into: inputBuffer)

        let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        )

        guard let outputFormat else {
            throw LocalWhisperError.audioPreparationFailed
        }

        if inputFormat.channelCount == 1,
            inputFormat.commonFormat == .pcmFormatFloat32,
            let channelData = inputBuffer.floatChannelData
        {
            let frames = Int(inputBuffer.frameLength)
            return Array(UnsafeBufferPointer(start: channelData[0], count: frames))
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw LocalWhisperError.audioPreparationFailed
        }

        guard
            let outputBuffer = AVAudioPCMBuffer(
                pcmFormat: outputFormat,
                frameCapacity: inputBuffer.frameLength
            )
        else {
            throw LocalWhisperError.audioPreparationFailed
        }

        var error: NSError?
        var didProvideInput = false
        let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            guard !didProvideInput else {
                outStatus.pointee = .noDataNow
                return nil
            }
            didProvideInput = true
            outStatus.pointee = .haveData
            return inputBuffer
        }

        guard status != .error, error == nil, let channelData = outputBuffer.floatChannelData else {
            throw LocalWhisperError.audioPreparationFailed
        }

        let frames = Int(outputBuffer.frameLength)
        return Array(UnsafeBufferPointer(start: channelData[0], count: frames))
    }
}

#if canImport(whisper)
    import whisper

    private actor WhisperCppContext {
        private var context: OpaquePointer?

        // Dedicated queue at .utility QoS so the OS preempts whisper threads
        // for UI work (.userInteractive) automatically — fixes processing-stage lag.
        nonisolated private static let inferenceQueue = DispatchQueue(
            label: "com.stet.whisper.inference",
            qos: .utility
        )

        deinit {
            if let context {
                whisper_free(context)
            }
        }

        func initializeModel(path: String) throws {
            guard context == nil else { return }

            var params = whisper_context_default_params()
            #if !targetEnvironment(simulator)
                params.flash_attn = true
            #else
                params.use_gpu = false
            #endif

            guard let loadedContext = whisper_init_from_file_with_params(path, params) else {
                throw LocalWhisperError.runtimeUnavailable
            }

            context = loadedContext
        }

        func releaseResources() {
            if let context {
                whisper_free(context)
                self.context = nil
            }
        }

        func transcribe(
            samples: [Float],
            languageCode: String?,
            prompt: String?
        ) async -> Bool {
            guard let ctx = context else { return false }

            let langCStr: [CChar]? = Self.normalizedLanguageCode(languageCode).map { Array($0.utf8CString) }
            let promptCStr: [CChar]? = prompt.flatMap { p in p.isEmpty ? nil : Array(p.utf8CString) }
            // Half of physical cores, capped at 4 — leaves enough headroom for UI rendering
            let nThreads = Int32(max(1, min(4, ProcessInfo.processInfo.processorCount / 2)))

            return await withCheckedContinuation { continuation in
                Self.inferenceQueue.async {
                    var success = true

                    func perform(langPtr: UnsafePointer<CChar>?, promptPtr: UnsafePointer<CChar>?) {
                        var params = whisper_full_default_params(WHISPER_SAMPLING_BEAM_SEARCH)
                        params.print_realtime = false
                        params.print_progress = false
                        params.print_timestamps = false
                        params.print_special = false
                        params.translate = false
                        params.no_context = true
                        params.temperature = 0
                        params.n_threads = nThreads
                        params.beam_search.beam_size = 5
                        params.language = langPtr
                        params.initial_prompt = promptPtr

                        whisper_reset_timings(ctx)

                        samples.withUnsafeBufferPointer { buffer in
                            if whisper_full(ctx, params, buffer.baseAddress, Int32(buffer.count)) != 0 {
                                success = false
                            }
                        }
                    }

                    if let lang = langCStr {
                        lang.withUnsafeBufferPointer { langBuf in
                            if let p = promptCStr {
                                p.withUnsafeBufferPointer { promptBuf in
                                    perform(langPtr: langBuf.baseAddress, promptPtr: promptBuf.baseAddress)
                                }
                            } else {
                                perform(langPtr: langBuf.baseAddress, promptPtr: nil)
                            }
                        }
                    } else if let p = promptCStr {
                        p.withUnsafeBufferPointer { promptBuf in
                            perform(langPtr: nil, promptPtr: promptBuf.baseAddress)
                        }
                    } else {
                        perform(langPtr: nil, promptPtr: nil)
                    }

                    continuation.resume(returning: success)
                }
            }
        }

        func transcriptionText() -> String {
            guard let context else { return "" }

            var text = ""
            for index in 0..<whisper_full_n_segments(context) {
                text += String(cString: whisper_full_get_segment_text(context, index))
            }
            return text
        }

        func detectedLanguageCode() -> String? {
            guard let context else { return nil }
            let langID = whisper_full_lang_id(context)
            guard langID != -1, let langStr = whisper_lang_str(langID) else {
                return nil
            }
            return String(cString: langStr)
        }

        private static func normalizedLanguageCode(_ languageCode: String?) -> String? {
            guard let languageCode else { return nil }
            let normalized = languageCode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !normalized.isEmpty else { return nil }

            if normalized == "zh-hans" || normalized == "zh-hant" {
                return "zh"
            }

            return normalized
        }
    }

    private actor WhisperCppLocalWhisperEngine: LocalWhisperEngine {
        private let modelURL: URL
        private let context = WhisperCppContext()

        init(modelURL: URL) {
            self.modelURL = modelURL
        }

        func prewarm() async throws {
            try await context.initializeModel(path: modelURL.path)
        }

        func transcribe(
            samples: [Float],
            languageCode: String?,
            prompt: String?
        ) async throws -> TranscriptionResult {
            try await prewarm()

            guard await context.transcribe(samples: samples, languageCode: languageCode, prompt: prompt) else {
                throw LocalWhisperError.transcriptionFailed
            }

            let text = await context.transcriptionText()
            let detectedLanguage = await context.detectedLanguageCode()
            return TranscriptionResult(text: text, languageCode: detectedLanguage)
        }

        func releaseResources() async {
            await context.releaseResources()
        }
    }
#endif
