#if os(macOS)
    import Foundation
    import StetAI
    import StetASR
    import os

    nonisolated protocol FunASRNanoEngine: Sendable {
        func prepare() async throws
        func transcribe(audioFileURL: URL, hotwords: String?) async throws -> String
        func releaseResources() async
        func encoderBackend() async -> String
    }

    extension FunASRNanoEngine {
        func encoderBackend() async -> String { "unknown" }
    }

    extension FunASRNanoRecognizer: FunASRNanoEngine {
        func transcribe(audioFileURL: URL, hotwords: String?) async throws -> String {
            try transcribe(audioFileURL: audioFileURL, maximumTokens: 512, hotwords: hotwords)
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
        static let shared = FunASRNanoContextManager()

        private var engine: (any FunASRNanoEngine)?
        private var loadedModelFiles: FunASRNanoModelFiles?
        private var loadTask: Task<any FunASRNanoEngine, Error>?
        private var loadingModelFiles: FunASRNanoModelFiles?
        private var loadGeneration = 0
        private var activeLeaseCount = 0
        private var cleanupRequested = false
        private var activeModelUses = 0
        private var maintenance = false

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
            await releaseLoadedEngine()
            try action()
            return true
        }

        private static func currentFiles(_ files: FunASRNanoModelFiles) -> FunASRNanoModelFiles {
            guard files.encoder.pathExtension == "mlmodelc",
                ANEModelReadiness.read(in: files.encoder.deletingLastPathComponent()) == nil
            else { return files }
            return FunASRNanoModelFiles(
                encoder: files.encoder.deletingLastPathComponent().appendingPathComponent("funasr-encoder-f16.gguf"),
                languageModel: files.languageModel, voiceActivityDetector: files.voiceActivityDetector)
        }

        func recordBackend(of engine: any FunASRNanoEngine, files: FunASRNanoModelFiles) async {
            guard files.encoder.pathExtension == "mlmodelc", await engine.encoderBackend() == "ggml-cpu" else { return }
            let directory = files.encoder.deletingLastPathComponent()
            if let receipt = ANEModelReadiness.installed(in: directory) {
                try? ANEModelReadiness.make(manifestHash: receipt.manifestHash, enabled: false).write(in: directory)
            }
            if loadedModelFiles == files { loadedModelFiles = Self.currentFiles(files) }
        }

        func loadModel(
            files: FunASRNanoModelFiles,
            engineFactory: @escaping @Sendable (FunASRNanoModelFiles) throws -> any FunASRNanoEngine
        ) async throws {
            try await ensureModel(files: files, engineFactory: engineFactory, permitsActiveLease: false)
        }

        func acquireLease(
            files: FunASRNanoModelFiles,
            engineFactory: @escaping @Sendable (FunASRNanoModelFiles) throws -> any FunASRNanoEngine
        ) async throws {
            let files = Self.currentFiles(files)
            guard activeLeaseCount == 0 || loadedModelFiles == files || loadingModelFiles == files else {
                throw FunASRNanoContextError.modelInUse
            }
            activeLeaseCount += 1
            do {
                try await ensureModel(files: files, engineFactory: engineFactory, permitsActiveLease: true)
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
            guard loadedModelFiles == Self.currentFiles(files) else { return nil }
            return engine
        }

        func cleanupResources() async {
            guard activeLeaseCount == 0, activeModelUses == 0, loadTask == nil, !maintenance else {
                cleanupRequested = true
                return
            }
            await releaseLoadedEngine()
        }

        private func ensureModel(
            files: FunASRNanoModelFiles,
            engineFactory: @escaping @Sendable (FunASRNanoModelFiles) throws -> any FunASRNanoEngine,
            permitsActiveLease: Bool
        ) async throws {
            let files = Self.currentFiles(files)
            if loadedModelFiles == files, engine != nil { return }
            if let loadTask {
                guard loadingModelFiles == files else { throw FunASRNanoContextError.modelInUse }
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
            loadingModelFiles = files
            let task = Task<any FunASRNanoEngine, Error> {
                if let previousEngine {
                    await previousEngine.releaseResources()
                }
                let newEngine = try engineFactory(files)
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
                await recordBackend(of: loadedEngine, files: files)
                if loadGeneration == generation {
                    engine = loadedEngine
                    loadedModelFiles = Self.currentFiles(files)
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
        private let engineFactory: @Sendable (FunASRNanoModelFiles) throws -> any FunASRNanoEngine
        private let contextManager: FunASRNanoContextManager
        private let logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "com.openwhispr.Stet",
            category: "FunASRNano"
        )

        init(
            modelManager: FunASRNanoModelManager = FunASRNanoModelManager(),
            engineFactory: @escaping @Sendable (FunASRNanoModelFiles) throws -> any FunASRNanoEngine = {
                FunASRNanoRecognizer(modelFiles: $0)
            },
            contextManager: FunASRNanoContextManager = .shared
        ) throws {
            _ = try modelManager.resolvedModelFiles()
            self.modelManager = modelManager
            self.engineFactory = engineFactory
            self.contextManager = contextManager
        }

        func prewarm() async throws {
            try await withModelAccess {
                try await contextManager.loadModel(
                    files: modelManager.resolvedModelFiles(), engineFactory: engineFactory)
            }
        }

        func acquireContextLease() async throws {
            try await withModelAccess {
                try await contextManager.acquireLease(
                    files: modelManager.resolvedModelFiles(), engineFactory: engineFactory)
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

            let modelFiles = try modelManager.resolvedModelFiles()
            let startedAt = ProcessInfo.processInfo.systemUptime
            let reusedEngine = await contextManager.engineIfLoaded(matching: modelFiles)
            let engine: any FunASRNanoEngine
            let isTransient: Bool
            if let reusedEngine {
                engine = reusedEngine
                isTransient = false
            } else {
                engine = try engineFactory(modelFiles)
                try await engine.prepare()
                await contextManager.recordBackend(of: engine, files: modelFiles)
                isTransient = true
            }

            do {
                let text = try await engine.transcribe(audioFileURL: fileURL, hotwords: prompt)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                await contextManager.recordBackend(of: engine, files: modelFiles)
                guard !text.isEmpty else {
                    throw SpeechServiceError.emptyTranscription
                }
                if isTransient {
                    await engine.releaseResources()
                }
                let elapsedMs = (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000
                logger.info(
                    "Fun-ASR Nano completed durationSeconds=\(audioDurationSeconds ?? -1, format: .fixed(precision: 3)) inferenceMs=\(elapsedMs, format: .fixed(precision: 1)) textChars=\(text.count) reusedLoadedContext=\(!isTransient)"
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
