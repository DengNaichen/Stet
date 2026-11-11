#if os(macOS)
    import Foundation
    import StetAI
    import StetASR
    import os

    nonisolated protocol FunASRNanoResidentEncoding: Sendable {
        var modelURL: URL { get }
        func warmup() throws
        func releaseResources()
    }

    extension FunASRNanoResidentEncoder: FunASRNanoResidentEncoding {}

    nonisolated protocol FunASRNanoEngine: Sendable {
        func prepare() async throws
        func transcribe(audioFileURL: URL, hotwords: String?) async throws -> String
        func releaseResources() async
        func encoderBackend() async -> String
        func updateResidentEncoder(_ encoder: (any FunASRNanoResidentEncoding)?) async
    }

    extension FunASRNanoEngine {
        func encoderBackend() async -> String { "unknown" }
        func updateResidentEncoder(_ encoder: (any FunASRNanoResidentEncoding)?) async {}
    }

    extension FunASRNanoRecognizer: FunASRNanoEngine {
        func transcribe(audioFileURL: URL, hotwords: String?) async throws -> String {
            try transcribe(audioFileURL: audioFileURL, maximumTokens: 512, hotwords: hotwords)
        }

        func updateResidentEncoder(_ encoder: (any FunASRNanoResidentEncoding)?) async {
            await updateResidentEncoder(encoder as? FunASRNanoResidentEncoder)
        }
    }

    enum FunASRNanoContextError: LocalizedError {
        case modelInUse

        var errorDescription: String? {
            switch self {
            case .modelInUse:
                "The loaded Fun-ASR Nano model is currently in use."
            }
        }
    }

    actor FunASRNanoContextManager {
        typealias ResidentEncoderFactory = @Sendable (URL) async throws -> any FunASRNanoResidentEncoding
        typealias ResidentEngineFactory =
            @Sendable (FunASRNanoModelFiles, (any FunASRNanoResidentEncoding)?) throws -> any FunASRNanoEngine

        static let shared = FunASRNanoContextManager()

        private struct ResidentKey: Equatable {
            let directory: URL
            let manifestHash: String
        }

        private struct LoadedResidentEncoder {
            let key: ResidentKey
            let encoder: any FunASRNanoResidentEncoding
        }

        private let residentEncoderFactory: ResidentEncoderFactory
        private let logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "com.openwhispr.Stet",
            category: "FunASRNanoContext"
        )

        private var residentEncoder: LoadedResidentEncoder?
        private var residentLoadTask: Task<Void, Never>?
        private var residentLoadKey: ResidentKey?
        private var failedResidentKey: ResidentKey?
        private var residentGeneration = 0

        private var engine: (any FunASRNanoEngine)?
        private var loadedModelFiles: FunASRNanoModelFiles?
        private var loadTask: Task<any FunASRNanoEngine, Error>?
        private var loadingModelFiles: FunASRNanoModelFiles?
        private var loadGeneration = 0
        private var activeLeaseCount = 0
        private var cleanupRequested = false
        private var activeModelUses = 0
        private var maintenance = false

        init(
            residentEncoderFactory: @escaping ResidentEncoderFactory =
                FunASRNanoContextManager.defaultResidentEncoderFactory
        ) {
            self.residentEncoderFactory = residentEncoderFactory
        }

        nonisolated static func defaultResidentEncoderFactory(url: URL) async throws -> any FunASRNanoResidentEncoding {
            try Task.checkCancellation()
            let task = Task.detached(priority: .utility) {
                try Task.checkCancellation()
                return try FunASRNanoResidentEncoder(modelURL: url)
            }
            return try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
        }

        var hasReadyResidentEncoder: Bool {
            residentEncoder != nil && residentLoadTask == nil
        }

        var isPreparingResidentEncoder: Bool {
            residentLoadTask != nil
        }

        func beginModelUse() async throws {
            while maintenance { try await Task.sleep(for: .milliseconds(20)) }
            try Task.checkCancellation()
            activeModelUses += 1
        }

        func endModelUse() async {
            activeModelUses = max(0, activeModelUses - 1)
            if activeModelUses == 0, activeLeaseCount == 0, cleanupRequested, loadTask == nil {
                await releaseLoadedEngine()
            }
        }

        func performModelMaintenance(_ action: @Sendable () throws -> Void) async throws -> Bool {
            guard !maintenance, activeModelUses == 0, activeLeaseCount == 0, loadTask == nil else { return false }
            maintenance = true
            defer { maintenance = false }
            await cancelAndDrainResidentLoad()
            await releaseLoadedEngine()
            releaseResidentEncoder()
            failedResidentKey = nil
            try action()
            return true
        }

        func scheduleResidentEncoderPreload(in directory: URL) {
            let standardized = directory.standardizedFileURL
            guard !maintenance else { return }
            guard let receipt = ANEModelReadiness.read(in: standardized) else {
                if residentEncoder?.key.directory == standardized,
                    activeModelUses == 0, activeLeaseCount == 0, loadTask == nil
                {
                    releaseResidentEncoder()
                }
                return
            }
            let key = ResidentKey(directory: standardized, manifestHash: receipt.manifestHash)
            failedResidentKey = nil
            let compiledURL = standardized.appendingPathComponent(
                FunASRNanoANEManifest.compiledName,
                isDirectory: true
            )
            startBackgroundResidentLoadIfNeeded(compiledURL: compiledURL, key: key)
        }

        func preloadResidentEncoder(in directory: URL) async {
            scheduleResidentEncoderPreload(in: directory)
            await residentLoadTask?.value
        }

        func handleSystemWake(in directory: URL) async {
            let standardized = directory.standardizedFileURL
            failedResidentKey = nil
            guard !maintenance else { return }
            guard let receipt = ANEModelReadiness.read(in: standardized) else {
                if residentEncoder?.key.directory == standardized,
                    activeModelUses == 0, activeLeaseCount == 0, loadTask == nil
                {
                    releaseResidentEncoder()
                }
                return
            }

            let key = ResidentKey(directory: standardized, manifestHash: receipt.manifestHash)
            let compiledURL = standardized.appendingPathComponent(
                FunASRNanoANEManifest.compiledName,
                isDirectory: true
            )

            if let existing = residentEncoder, existing.key == key, residentLoadTask == nil {
                guard activeModelUses == 0, activeLeaseCount == 0, loadTask == nil else { return }
                if let recognizer = engine as? FunASRNanoRecognizer,
                    let loaded = loadedModelFiles,
                    loaded.encoder.deletingLastPathComponent().standardizedFileURL == standardized
                {
                    await recognizer.updateResidentEncoder(nil)
                    loadedModelFiles = Self.cpuModelFiles(from: loaded)
                }
                residentEncoder = nil
                startBackgroundWakeRewarm(existing: existing.encoder, compiledURL: compiledURL, key: key)
                await residentLoadTask?.value
                return
            }

            await preloadResidentEncoder(in: standardized)
        }

        private static func cpuModelFiles(from files: FunASRNanoModelFiles) -> FunASRNanoModelFiles {
            FunASRNanoModelFiles(
                encoder: files.encoder.deletingLastPathComponent().appendingPathComponent("funasr-encoder-f16.gguf"),
                languageModel: files.languageModel,
                voiceActivityDetector: files.voiceActivityDetector
            )
        }

        private static func sharesBaseAssets(_ lhs: FunASRNanoModelFiles, _ rhs: FunASRNanoModelFiles) -> Bool {
            lhs.languageModel == rhs.languageModel && lhs.voiceActivityDetector == rhs.voiceActivityDetector
        }

        private func selectExecutionFiles(
            for requested: FunASRNanoModelFiles,
            allowActiveLeaseReuse: Bool
        ) -> (files: FunASRNanoModelFiles, residentEncoder: (any FunASRNanoResidentEncoding)?) {
            let directory = requested.encoder.deletingLastPathComponent().standardizedFileURL
            if allowActiveLeaseReuse, activeLeaseCount > 0,
                let activeFiles = loadedModelFiles ?? loadingModelFiles,
                Self.sharesBaseAssets(activeFiles, requested)
            {
                let resident = activeFiles.encoder.pathExtension == "mlmodelc" ? residentEncoder?.encoder : nil
                return (activeFiles, resident)
            }

            guard requested.encoder.pathExtension == "mlmodelc",
                let receipt = ANEModelReadiness.read(in: directory)
            else {
                if residentEncoder?.key.directory == directory,
                    activeModelUses == 0, activeLeaseCount == 0, loadTask == nil
                {
                    releaseResidentEncoder()
                }
                let fallback =
                    requested.encoder.pathExtension == "mlmodelc" ? Self.cpuModelFiles(from: requested) : requested
                return (fallback, nil)
            }

            let key = ResidentKey(directory: directory, manifestHash: receipt.manifestHash)
            if let loadedResident = residentEncoder, loadedResident.key == key, residentLoadTask == nil {
                return (requested, loadedResident.encoder)
            }

            if failedResidentKey != key {
                startBackgroundResidentLoadIfNeeded(compiledURL: requested.encoder, key: key)
            }
            return (Self.cpuModelFiles(from: requested), nil)
        }

        func prepareTransientSelection(
            for requested: FunASRNanoModelFiles
        ) -> (files: FunASRNanoModelFiles, residentEncoder: (any FunASRNanoResidentEncoding)?) {
            selectExecutionFiles(for: requested, allowActiveLeaseReuse: true)
        }

        func recordBackend(of engine: any FunASRNanoEngine, files: FunASRNanoModelFiles) async {
            guard files.encoder.pathExtension == "mlmodelc", await engine.encoderBackend() == "ggml-cpu" else { return }
            let directory = files.encoder.deletingLastPathComponent()
            if let receipt = ANEModelReadiness.installed(in: directory) {
                try? ANEModelReadiness.make(manifestHash: receipt.manifestHash, enabled: false).write(in: directory)
            }
            releaseResidentEncoder()
            if loadedModelFiles == files { loadedModelFiles = Self.cpuModelFiles(from: files) }
        }

        func loadModel(
            files: FunASRNanoModelFiles,
            engineFactory: @escaping @Sendable (FunASRNanoModelFiles) throws -> any FunASRNanoEngine
        ) async throws {
            try await loadModel(files: files) { selectedFiles, _ in
                try engineFactory(selectedFiles)
            }
        }

        func loadModel(
            files: FunASRNanoModelFiles,
            residentEngineFactory: @escaping ResidentEngineFactory
        ) async throws {
            try await ensureModel(
                files: files,
                residentEngineFactory: residentEngineFactory,
                permitsActiveLease: false
            )
        }

        func acquireLease(
            files: FunASRNanoModelFiles,
            engineFactory: @escaping @Sendable (FunASRNanoModelFiles) throws -> any FunASRNanoEngine
        ) async throws {
            try await acquireLease(files: files) { selectedFiles, _ in
                try engineFactory(selectedFiles)
            }
        }

        func acquireLease(
            files: FunASRNanoModelFiles,
            residentEngineFactory: @escaping ResidentEngineFactory
        ) async throws {
            let selection = selectExecutionFiles(for: files, allowActiveLeaseReuse: true)
            let effectiveFiles = selection.files
            guard activeLeaseCount == 0 || loadedModelFiles == effectiveFiles || loadingModelFiles == effectiveFiles
            else {
                throw FunASRNanoContextError.modelInUse
            }
            activeLeaseCount += 1
            do {
                try await ensureModel(
                    files: files,
                    residentEngineFactory: residentEngineFactory,
                    permitsActiveLease: true
                )
            } catch {
                activeLeaseCount -= 1
                throw error
            }
        }

        func releaseLease() async {
            guard activeLeaseCount > 0 else { return }
            activeLeaseCount -= 1
            if activeLeaseCount == 0, activeModelUses == 0, cleanupRequested {
                await releaseLoadedEngine()
            }
        }

        func engineIfLoaded(matching files: FunASRNanoModelFiles) -> (any FunASRNanoEngine)? {
            let selection = selectExecutionFiles(for: files, allowActiveLeaseReuse: true)
            guard loadedModelFiles == selection.files else { return nil }
            return engine
        }

        /// Releases only the Qwen3 language model context (`stet_funasr_context`),
        /// keeping any warm resident ANE encoder and its bucket buffers in memory.
        func cleanupResources() async {
            guard activeLeaseCount == 0, activeModelUses == 0, loadTask == nil, !maintenance else {
                cleanupRequested = true
                return
            }
            await releaseLoadedEngine()
        }

        private func ensureModel(
            files: FunASRNanoModelFiles,
            residentEngineFactory: @escaping ResidentEngineFactory,
            permitsActiveLease: Bool
        ) async throws {
            let selection = selectExecutionFiles(for: files, allowActiveLeaseReuse: permitsActiveLease)
            let effectiveFiles = selection.files
            let resident = selection.residentEncoder

            if loadedModelFiles == effectiveFiles, engine != nil { return }
            if let loadTask {
                guard loadingModelFiles == effectiveFiles else { throw FunASRNanoContextError.modelInUse }
                _ = try await loadTask.value
                return
            }
            guard permitsActiveLease || activeLeaseCount == 0 else {
                throw FunASRNanoContextError.modelInUse
            }

            let previousEngine = engine
            engine = nil
            loadedModelFiles = nil
            loadGeneration += 1
            let generation = loadGeneration
            loadingModelFiles = effectiveFiles
            let task = Task<any FunASRNanoEngine, Error> {
                if let previousEngine {
                    await previousEngine.releaseResources()
                }
                let newEngine = try residentEngineFactory(effectiveFiles, resident)
                do {
                    try await newEngine.prepare()
                    return newEngine
                } catch {
                    await newEngine.releaseResources()
                    throw error
                }
            }
            loadTask = task

            do {
                let loadedEngine = try await task.value
                await recordBackend(of: loadedEngine, files: effectiveFiles)
                if loadGeneration == generation {
                    engine = loadedEngine
                    if effectiveFiles.encoder.pathExtension == "mlmodelc",
                        ANEModelReadiness.read(in: effectiveFiles.encoder.deletingLastPathComponent()) == nil
                    {
                        loadedModelFiles = Self.cpuModelFiles(from: effectiveFiles)
                    } else {
                        loadedModelFiles = effectiveFiles
                    }
                    loadTask = nil
                    loadingModelFiles = nil
                    if activeLeaseCount == 0, activeModelUses == 0, cleanupRequested {
                        await releaseLoadedEngine()
                    }
                }
            } catch {
                if loadGeneration == generation {
                    loadTask = nil
                    loadingModelFiles = nil
                }
                throw error
            }
        }

        private func startBackgroundResidentLoadIfNeeded(compiledURL: URL, key: ResidentKey) {
            if let residentEncoder, residentEncoder.key == key, residentLoadTask == nil { return }
            if residentLoadTask != nil, residentLoadKey == key { return }

            residentGeneration += 1
            let generation = residentGeneration
            residentLoadTask?.cancel()
            residentLoadKey = key
            let factory = residentEncoderFactory
            let startedAt = ProcessInfo.processInfo.systemUptime

            residentLoadTask = Task(priority: .utility) {
                do {
                    let loaded = try await factory(compiledURL)
                    await self.finishBackgroundResidentLoad(
                        result: .success(loaded),
                        key: key,
                        generation: generation,
                        startedAt: startedAt
                    )
                } catch {
                    await self.finishBackgroundResidentLoad(
                        result: .failure(error),
                        key: key,
                        generation: generation,
                        startedAt: startedAt
                    )
                }
            }
        }

        private func startBackgroundWakeRewarm(
            existing: any FunASRNanoResidentEncoding,
            compiledURL: URL,
            key: ResidentKey
        ) {
            residentGeneration += 1
            let generation = residentGeneration
            residentLoadTask?.cancel()
            residentLoadKey = key
            let factory = residentEncoderFactory
            let startedAt = ProcessInfo.processInfo.systemUptime

            residentLoadTask = Task(priority: .utility) {
                do {
                    try Task.checkCancellation()
                    let rewarmed: any FunASRNanoResidentEncoding
                    do {
                        try await Task.detached(priority: .utility) {
                            try existing.warmup()
                        }.value
                        rewarmed = existing
                    } catch is CancellationError {
                        existing.releaseResources()
                        throw CancellationError()
                    } catch {
                        existing.releaseResources()
                        rewarmed = try await factory(compiledURL)
                    }
                    await self.finishBackgroundResidentLoad(
                        result: .success(rewarmed),
                        key: key,
                        generation: generation,
                        startedAt: startedAt
                    )
                } catch {
                    existing.releaseResources()
                    await self.finishBackgroundResidentLoad(
                        result: .failure(error),
                        key: key,
                        generation: generation,
                        startedAt: startedAt
                    )
                }
            }
        }

        private func finishBackgroundResidentLoad(
            result: Result<any FunASRNanoResidentEncoding, Error>,
            key: ResidentKey,
            generation: Int,
            startedAt: TimeInterval
        ) async {
            switch result {
            case .success(let newEncoder):
                guard residentGeneration == generation,
                    !maintenance,
                    ANEModelReadiness.read(in: key.directory)?.manifestHash == key.manifestHash
                else {
                    newEncoder.releaseResources()
                    if residentGeneration == generation {
                        residentLoadTask = nil
                        residentLoadKey = nil
                    }
                    return
                }
                if let previous = residentEncoder, previous.encoder as AnyObject !== newEncoder as AnyObject {
                    previous.encoder.releaseResources()
                }
                residentEncoder = LoadedResidentEncoder(key: key, encoder: newEncoder)
                failedResidentKey = nil
                residentLoadTask = nil
                residentLoadKey = nil
                let elapsedMs = (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000
                logger.notice(
                    "Fun-ASR Nano resident ANE encoder ready in \(elapsedMs, format: .fixed(precision: 1))ms"
                )
                if activeModelUses == 0, activeLeaseCount == 0, loadTask == nil,
                    let recognizer = engine as? FunASRNanoRecognizer,
                    let loaded = loadedModelFiles,
                    loaded.encoder.deletingLastPathComponent().standardizedFileURL == key.directory
                {
                    await recognizer.updateResidentEncoder(newEncoder)
                    loadedModelFiles = FunASRNanoModelFiles(
                        encoder: key.directory.appendingPathComponent(
                            FunASRNanoANEManifest.compiledName,
                            isDirectory: true
                        ),
                        languageModel: loaded.languageModel,
                        voiceActivityDetector: loaded.voiceActivityDetector
                    )
                }
            case .failure(let error):
                guard residentGeneration == generation else { return }
                residentLoadTask = nil
                residentLoadKey = nil
                if !(error is CancellationError) {
                    failedResidentKey = key
                    logger.warning(
                        "Fun-ASR Nano resident ANE encoder load failed; staying on CPU: \(error.localizedDescription, privacy: .public)"
                    )
                }
            }
        }

        private func cancelAndDrainResidentLoad() async {
            residentGeneration += 1
            let task = residentLoadTask
            residentLoadTask = nil
            residentLoadKey = nil
            task?.cancel()
            await task?.value
        }

        private func releaseResidentEncoder() {
            residentEncoder?.encoder.releaseResources()
            residentEncoder = nil
        }

        private func releaseLoadedEngine() async {
            if let engine {
                await engine.releaseResources()
            }
            engine = nil
            loadedModelFiles = nil
            cleanupRequested = false
        }
    }

    final class FunASRNanoTranscriptionService: AudioFileTranscriptionService, @unchecked Sendable {
        private let modelManager: FunASRNanoModelManager
        private let residentEngineFactory: FunASRNanoContextManager.ResidentEngineFactory
        private let contextManager: FunASRNanoContextManager
        private let logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "com.openwhispr.Stet",
            category: "FunASRNano"
        )

        init(
            modelManager: FunASRNanoModelManager = FunASRNanoModelManager(),
            residentEngineFactory: @escaping FunASRNanoContextManager.ResidentEngineFactory = { files, resident in
                FunASRNanoRecognizer(
                    modelFiles: files,
                    residentEncoder: resident as? FunASRNanoResidentEncoder
                )
            },
            contextManager: FunASRNanoContextManager = .shared
        ) throws {
            _ = try modelManager.resolvedModelFiles()
            self.modelManager = modelManager
            self.residentEngineFactory = residentEngineFactory
            self.contextManager = contextManager
        }

        convenience init(
            modelManager: FunASRNanoModelManager = FunASRNanoModelManager(),
            engineFactory: @escaping @Sendable (FunASRNanoModelFiles) throws -> any FunASRNanoEngine,
            contextManager: FunASRNanoContextManager = .shared
        ) throws {
            try self.init(
                modelManager: modelManager,
                residentEngineFactory: { files, _ in try engineFactory(files) },
                contextManager: contextManager
            )
        }

        func isPrewarmed() async -> Bool {
            guard let files = try? modelManager.resolvedModelFiles() else { return false }
            return await contextManager.engineIfLoaded(matching: files) != nil
        }

        func prewarm() async throws {
            try await withModelAccess {
                try await contextManager.loadModel(
                    files: modelManager.resolvedModelFiles(),
                    residentEngineFactory: residentEngineFactory
                )
            }
        }

        func acquireContextLease() async throws {
            try await withModelAccess {
                try await contextManager.acquireLease(
                    files: modelManager.resolvedModelFiles(),
                    residentEngineFactory: residentEngineFactory
                )
            }
        }

        func releaseContextLease() async {
            await contextManager.releaseLease()
        }

        private func withModelAccess<T: Sendable>(_ operation: () async throws -> T) async throws -> T {
            try await contextManager.beginModelUse()
            do {
                let value = try await operation()
                await contextManager.endModelUse()
                return value
            } catch {
                await contextManager.endModelUse()
                throw error
            }
        }

        func transcribe(
            audioFileAt fileURL: URL, languageCode: String?, prompt: String?, audioDurationSeconds: TimeInterval?
        ) async throws -> TranscriptionResult {
            try await withModelAccess {
                try await transcribeUsingCurrentModel(
                    audioFileAt: fileURL, languageCode: languageCode,
                    prompt: prompt, audioDurationSeconds: audioDurationSeconds)
            }
        }

        private func transcribeUsingCurrentModel(
            audioFileAt fileURL: URL,
            languageCode: String?,
            prompt: String?,
            audioDurationSeconds: TimeInterval?
        ) async throws -> TranscriptionResult {
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                throw OpenAIError.fileNotFound(fileURL)
            }

            let requestedFiles = try modelManager.resolvedModelFiles()
            let startedAt = ProcessInfo.processInfo.systemUptime
            let reusedEngine = await contextManager.engineIfLoaded(matching: requestedFiles)
            let engine: any FunASRNanoEngine
            let effectiveFiles: FunASRNanoModelFiles
            let isTransient: Bool
            if let reusedEngine {
                let selection = await contextManager.prepareTransientSelection(for: requestedFiles)
                engine = reusedEngine
                effectiveFiles = selection.files
                isTransient = false
            } else {
                let selection = await contextManager.prepareTransientSelection(for: requestedFiles)
                effectiveFiles = selection.files
                engine = try residentEngineFactory(effectiveFiles, selection.residentEncoder)
                try await engine.prepare()
                await contextManager.recordBackend(of: engine, files: effectiveFiles)
                isTransient = true
            }

            do {
                let text = try await engine.transcribe(audioFileURL: fileURL, hotwords: prompt)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let backend = await engine.encoderBackend()
                await contextManager.recordBackend(of: engine, files: effectiveFiles)
                guard !text.isEmpty else {
                    throw SpeechServiceError.emptyTranscription
                }
                if isTransient {
                    await engine.releaseResources()
                }
                let elapsedMs = (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000
                logger.info(
                    "Fun-ASR Nano completed durationSeconds=\(audioDurationSeconds ?? -1, format: .fixed(precision: 3)) inferenceMs=\(elapsedMs, format: .fixed(precision: 1)) textChars=\(text.count) reusedLoadedContext=\(!isTransient) encoderBackend=\(backend, privacy: .public)"
                )
                return TranscriptionResult(text: text, languageCode: nil)
            } catch {
                if isTransient {
                    await engine.releaseResources()
                }
                logger.error("Fun-ASR Nano failed: \(error.localizedDescription, privacy: .public)")
                throw error
            }
        }
    }
#endif
