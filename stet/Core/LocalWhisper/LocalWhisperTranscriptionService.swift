@preconcurrency import AVFoundation
import Foundation
import os

protocol LocalWhisperEngine: Sendable {
    func prewarm() async throws
    func transcribe(
        samples: [Float],
        languageCode: String?,
        prompt: String?
    ) async throws -> String
}

enum LocalWhisperEngineFactory {
    private static let sharedCache = SharedLocalWhisperEngineCache()

    nonisolated static var isRuntimeAvailable: Bool {
        #if canImport(whisper)
            true
        #else
            false
        #endif
    }

    nonisolated static func acquireEngine(
        modelURL: URL,
        createEngine: () throws -> any LocalWhisperEngine
    ) rethrows -> LocalWhisperEngineLease {
        try sharedCache.acquireLease(for: modelURL, createEngine: createEngine)
    }

    nonisolated static func invalidateSharedEngines() {
        sharedCache.invalidateAll()
    }

    nonisolated static func makeEngineLease(modelURL: URL) throws -> LocalWhisperEngineLease {
        #if canImport(whisper)
            return try acquireEngine(modelURL: modelURL) {
                WhisperCppLocalWhisperEngine(modelURL: modelURL)
            }
        #else
            throw LocalWhisperError.runtimeUnavailable
        #endif
    }
}

final class SharedLocalWhisperEngineCache: @unchecked Sendable {
    private struct Entry {
        let engine: any LocalWhisperEngine
        var activeLeaseCount: Int
    }

    private let lock = NSLock()
    private var entriesByModelPath: [String: Entry] = [:]

    deinit {
        invalidateAll()
    }

    func acquireLease(
        for modelURL: URL,
        createEngine: () throws -> any LocalWhisperEngine
    ) rethrows -> LocalWhisperEngineLease {
        let modelPath = modelURL.standardizedFileURL.path

        lock.lock()
        defer { lock.unlock() }

        if var entry = entriesByModelPath[modelPath] {
            entry.activeLeaseCount += 1
            entriesByModelPath[modelPath] = entry
            return LocalWhisperEngineLease(
                modelPath: modelPath,
                engine: entry.engine,
                cache: self
            )
        }

        let engine = try createEngine()
        entriesByModelPath[modelPath] = Entry(
            engine: engine,
            activeLeaseCount: 1
        )
        return LocalWhisperEngineLease(modelPath: modelPath, engine: engine, cache: self)
    }

    func releaseLease(for modelPath: String) {
        lock.lock()
        guard var entry = entriesByModelPath[modelPath] else {
            lock.unlock()
            return
        }

        if entry.activeLeaseCount > 0 {
            entry.activeLeaseCount -= 1
        }

        if entry.activeLeaseCount == 0 {
            entriesByModelPath.removeValue(forKey: modelPath)
        } else {
            entriesByModelPath[modelPath] = entry
        }
        lock.unlock()
    }

    func invalidateAll() {
        lock.lock()
        entriesByModelPath.removeAll()
        lock.unlock()
    }
}

final class LocalWhisperEngineLease: @unchecked Sendable {
    let engine: any LocalWhisperEngine

    private let modelPath: String
    private let cache: SharedLocalWhisperEngineCache

    fileprivate init(
        modelPath: String,
        engine: any LocalWhisperEngine,
        cache: SharedLocalWhisperEngineCache
    ) {
        self.modelPath = modelPath
        self.engine = engine
        self.cache = cache
    }

    deinit {
        cache.releaseLease(for: modelPath)
    }
}

final class LocalWhisperTranscriptionService: AudioFileTranscriptionService, @unchecked Sendable {
    private let engineLeaseSource: LocalWhisperEngineLeaseSource
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.openwhispr.Stet", category: "LocalWhisper")

    init(
        modelManager: LocalWhisperModelManager,
        engineFactory: @escaping @Sendable (URL) throws -> LocalWhisperEngineLease = {
            try LocalWhisperEngineFactory.makeEngineLease(modelURL: $0)
        }
    ) throws {
        let modelURL = try modelManager.resolvedModelURL()
        self.engineLeaseSource = LocalWhisperEngineLeaseSource(
            modelURL: modelURL,
            engineFactory: engineFactory
        )
    }

    func prewarm() async throws {
        let engineLease = try await engineLeaseSource.engineLease()
        try await engineLease.engine.prewarm()
    }

    func transcribe(
        audioFileAt fileURL: URL,
        languageCode: String?,
        prompt: String?,
        audioDurationSeconds: TimeInterval?
    ) async throws -> String {
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

        let inferenceStartedAt = ProcessInfo.processInfo.systemUptime
        let transcript: String
        do {
            let engineLease = try await engineLeaseSource.engineLease()
            try await engineLease.engine.prewarm()
            transcript = try await engineLease.engine.transcribe(
                samples: samples,
                languageCode: languageCode,
                prompt: prompt
            ).trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            AppLogger.error(
                "LocalWhisper failed audioDurationSeconds=\(Self.formatOptionalDurationSeconds(audioDurationSeconds)) samplePreparationMs=\(Self.formatMilliseconds(samplePreparationMs)) inferenceMs=\(Self.formatMilliseconds(Self.elapsedMilliseconds(since: inferenceStartedAt))) languageCode=\(languageCode ?? "auto") promptChars=\(prompt?.count ?? 0) error=\(error.localizedDescription)",
                category: .perfTrace
            )
            throw error
        }
        let inferenceMs = Self.elapsedMilliseconds(since: inferenceStartedAt)
        let totalMs = Self.elapsedMilliseconds(since: startedAt)

        guard !transcript.isEmpty else {
            throw SpeechServiceError.emptyTranscription
        }

        AppLogger.info(
            "LocalWhisper completed audioDurationSeconds=\(Self.formatOptionalDurationSeconds(audioDurationSeconds)) sampleCount=\(samples.count) samplePreparationMs=\(Self.formatMilliseconds(samplePreparationMs)) inferenceMs=\(Self.formatMilliseconds(inferenceMs)) totalMs=\(Self.formatMilliseconds(totalMs)) textChars=\(transcript.count) languageCode=\(languageCode ?? "auto") promptChars=\(prompt?.count ?? 0)",
            category: .perfTrace
        )

        return transcript
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

private actor LocalWhisperEngineLeaseSource {
    private let modelURL: URL
    private let engineFactory: @Sendable (URL) throws -> LocalWhisperEngineLease
    private var cachedLease: LocalWhisperEngineLease?

    init(
        modelURL: URL,
        engineFactory: @escaping @Sendable (URL) throws -> LocalWhisperEngineLease
    ) {
        self.modelURL = modelURL
        self.engineFactory = engineFactory
    }

    func engineLease() throws -> LocalWhisperEngineLease {
        if let cachedLease {
            return cachedLease
        }

        let newLease = try engineFactory(modelURL)
        cachedLease = newLease
        return newLease
    }
}

#if canImport(whisper)
    import whisper

    private actor WhisperCppContext {
        private var context: OpaquePointer?
        private var languageCString: [CChar]?
        private var promptCString: [CChar]?

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

        func transcribe(
            samples: [Float],
            languageCode: String?,
            prompt: String?
        ) -> Bool {
            guard let context else { return false }

            if let normalizedLanguageCode = Self.normalizedLanguageCode(languageCode) {
                languageCString = Array(normalizedLanguageCode.utf8CString)
            } else {
                languageCString = nil
            }

            if let prompt, !prompt.isEmpty {
                promptCString = Array(prompt.utf8CString)
            } else {
                promptCString = nil
            }

            var success = true

            // Correctly nest pointers to ensure they remain valid during whisper_full call
            func performTranscription(langPtr: UnsafePointer<CChar>?, promptPtr: UnsafePointer<CChar>?) {
                var params = whisper_full_default_params(WHISPER_SAMPLING_BEAM_SEARCH)
                params.print_realtime = false
                params.print_progress = false
                params.print_timestamps = false
                params.print_special = false
                params.translate = false
                params.no_context = true
                params.temperature = 0
                params.n_threads = Int32(max(1, min(8, ProcessInfo.processInfo.processorCount - 2)))
                params.beam_search.beam_size = 2
                params.language = langPtr
                params.initial_prompt = promptPtr

                whisper_reset_timings(context)

                samples.withUnsafeBufferPointer { buffer in
                    if whisper_full(context, params, buffer.baseAddress, Int32(buffer.count)) != 0 {
                        success = false
                    }
                }
            }

            if let languageCString = languageCString {
                languageCString.withUnsafeBufferPointer { langBuf in
                    if let promptCString = promptCString {
                        promptCString.withUnsafeBufferPointer { promptBuf in
                            performTranscription(langPtr: langBuf.baseAddress, promptPtr: promptBuf.baseAddress)
                        }
                    } else {
                        performTranscription(langPtr: langBuf.baseAddress, promptPtr: nil)
                    }
                }
            } else {
                if let promptCString = promptCString {
                    promptCString.withUnsafeBufferPointer { promptBuf in
                        performTranscription(langPtr: nil, promptPtr: promptBuf.baseAddress)
                    }
                } else {
                    performTranscription(langPtr: nil, promptPtr: nil)
                }
            }

            languageCString = nil
            promptCString = nil
            return success
        }

        func transcriptionText() -> String {
            guard let context else { return "" }

            var text = ""
            for index in 0..<whisper_full_n_segments(context) {
                text += String(cString: whisper_full_get_segment_text(context, index))
            }
            return text
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
        ) async throws -> String {
            try await prewarm()

            guard await context.transcribe(samples: samples, languageCode: languageCode, prompt: prompt) else {
                throw LocalWhisperError.transcriptionFailed
            }

            return await context.transcriptionText()
        }
    }
#endif
