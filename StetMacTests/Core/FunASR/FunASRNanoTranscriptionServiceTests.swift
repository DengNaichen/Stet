#if os(macOS)
    import Foundation
    import StetASR
    import Testing

    @testable import Stet

    @MainActor
    @Suite("Fun-ASR Nano Transcription Service", .serialized)
    struct FunASRNanoTranscriptionServiceTests {
        @Test func prewarmLoadsAndTranscriptionReusesEngine() async throws {
            let modelManager = try makeModelManager()
            let audioURL = try makeAudioFile()
            let contextManager = FunASRNanoContextManager()
            let engines = FunASREngineStore()
            let service = try FunASRNanoTranscriptionService(
                modelManager: modelManager,
                engineFactory: { _ in
                    let engine = StubFunASREngine(text: "你好 Stet")
                    engines.append(engine)
                    return engine
                },
                contextManager: contextManager
            )

            try await service.prewarm()
            let result = try await service.transcribe(
                audioFileAt: audioURL,
                languageCode: "zh",
                prompt: "Stet",
                audioDurationSeconds: 1
            )

            #expect(result.text == "你好 Stet")
            #expect(result.languageCode == nil)
            let engine = try #require(engines.snapshot().first)
            #expect(await engine.prepareCallCount == 1)
            #expect(await engine.transcribeCallCount == 1)
            #expect(await engine.releaseCallCount == 0)
            await contextManager.cleanupResources()
            #expect(await engine.releaseCallCount == 1)
        }

        @Test func transcriptionWithoutPrewarmUsesTransientEngine() async throws {
            let modelManager = try makeModelManager()
            let audioURL = try makeAudioFile()
            let engines = FunASREngineStore()
            let service = try FunASRNanoTranscriptionService(
                modelManager: modelManager,
                engineFactory: { _ in
                    let engine = StubFunASREngine(text: "hello")
                    engines.append(engine)
                    return engine
                },
                contextManager: FunASRNanoContextManager()
            )

            _ = try await service.transcribe(
                audioFileAt: audioURL,
                languageCode: nil,
                prompt: nil,
                audioDurationSeconds: nil
            )

            let engine = try #require(engines.snapshot().first)
            #expect(await engine.prepareCallCount == 1)
            #expect(await engine.transcribeCallCount == 1)
            #expect(await engine.releaseCallCount == 1)
        }

        private func makeModelManager() throws -> FunASRNanoModelManager {
            let directory = TestSupport.temporaryDirectoryURL()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let manager = FunASRNanoModelManager(modelsDirectoryProvider: { directory })
            for file in try manager.modelFiles().allFiles {
                try Data("model".utf8).write(to: file)
            }
            return manager
        }

        private func makeAudioFile() throws -> URL {
            let url = TestSupport.temporaryFileURL("funasr-audio", ext: "wav")
            try Data("audio".utf8).write(to: url)
            return url
        }
    }

    private actor StubFunASREngine: FunASRNanoEngine {
        private let text: String
        private(set) var prepareCallCount = 0
        private(set) var transcribeCallCount = 0
        private(set) var releaseCallCount = 0

        init(text: String) {
            self.text = text
        }

        func prepare() async throws {
            prepareCallCount += 1
        }

        func transcribe(audioFileURL _: URL) async throws -> String {
            transcribeCallCount += 1
            return text
        }

        func releaseResources() async {
            releaseCallCount += 1
        }
    }

    private final class FunASREngineStore: @unchecked Sendable {
        private let lock = NSLock()
        private var engines: [StubFunASREngine] = []

        func append(_ engine: StubFunASREngine) {
            lock.lock()
            defer { lock.unlock() }
            engines.append(engine)
        }

        func snapshot() -> [StubFunASREngine] {
            lock.lock()
            defer { lock.unlock() }
            return engines
        }
    }
#endif
