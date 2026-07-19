#if os(macOS)
    import Foundation
    import StetAI
    import StetASR
    import os

    protocol FunASRNanoEngine: Sendable {
        func prepare() async throws
        func transcribe(audioFileURL: URL, hotwords: String?) async throws -> String
        func releaseResources() async
    }

    extension FunASRNanoRecognizer: FunASRNanoEngine {
        func transcribe(audioFileURL: URL, hotwords: String?) async throws -> String {
            try transcribe(audioFileURL: audioFileURL, maximumTokens: 512, hotwords: hotwords)
        }
    }

    actor FunASRNanoContextManager {
        static let shared = FunASRNanoContextManager()

        private var engine: (any FunASRNanoEngine)?
        private var loadedModelFiles: FunASRNanoModelFiles?

        func loadModel(
            files: FunASRNanoModelFiles,
            engineFactory: @Sendable (FunASRNanoModelFiles) throws -> any FunASRNanoEngine
        ) async throws {
            if loadedModelFiles == files, engine != nil { return }
            if let engine {
                await engine.releaseResources()
            }

            self.engine = nil
            loadedModelFiles = nil
            let newEngine = try engineFactory(files)
            do {
                try await newEngine.prepare()
                engine = newEngine
                loadedModelFiles = files
            } catch {
                await newEngine.releaseResources()
                throw error
            }
        }

        func engineIfLoaded(matching files: FunASRNanoModelFiles) -> (any FunASRNanoEngine)? {
            guard loadedModelFiles == files else { return nil }
            return engine
        }

        func cleanupResources() async {
            if let engine {
                await engine.releaseResources()
            }
            engine = nil
            loadedModelFiles = nil
        }
    }

    final class FunASRNanoTranscriptionService: AudioFileTranscriptionService, @unchecked Sendable {
        private let modelFiles: FunASRNanoModelFiles
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
            self.modelFiles = try modelManager.resolvedModelFiles()
            self.engineFactory = engineFactory
            self.contextManager = contextManager
        }

        func prewarm() async throws {
            try await contextManager.loadModel(files: modelFiles, engineFactory: engineFactory)
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
            let reusedEngine = await contextManager.engineIfLoaded(matching: modelFiles)
            let engine: any FunASRNanoEngine
            let isTransient: Bool
            if let reusedEngine {
                engine = reusedEngine
                isTransient = false
            } else {
                engine = try engineFactory(modelFiles)
                try await engine.prepare()
                isTransient = true
            }

            do {
                let text = try await engine.transcribe(audioFileURL: fileURL, hotwords: prompt)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
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
