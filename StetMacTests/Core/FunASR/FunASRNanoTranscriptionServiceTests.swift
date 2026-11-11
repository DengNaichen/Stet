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
            #expect(await engine.receivedHotwords == ["Stet"])
            #expect(await engine.releaseCallCount == 0)
            await contextManager.cleanupResources()
            #expect(await engine.releaseCallCount == 1)
        }

        @Test func contextLeaseDefersCleanupUntilReleased() async throws {
            let modelManager = try makeModelManager()
            let engines = FunASREngineStore()
            let contextManager = FunASRNanoContextManager()
            let service = try FunASRNanoTranscriptionService(
                modelManager: modelManager,
                engineFactory: { _ in
                    let engine = StubFunASREngine(text: "leased")
                    engines.append(engine)
                    return engine
                },
                contextManager: contextManager
            )

            try await service.acquireContextLease()
            let engine = try #require(engines.snapshot().first)
            #expect(await engine.prepareCallCount == 1)

            await contextManager.cleanupResources()
            #expect(await engine.releaseCallCount == 0)

            await service.releaseContextLease()
            #expect(await engine.releaseCallCount == 1)
        }

        @Test func multipleLeasesPrepareOnceAndReleaseAfterLastLease() async throws {
            let modelManager = try makeModelManager()
            let engines = FunASREngineStore()
            let contextManager = FunASRNanoContextManager()
            let service = try FunASRNanoTranscriptionService(
                modelManager: modelManager,
                engineFactory: { _ in
                    let engine = StubFunASREngine(text: "shared")
                    engines.append(engine)
                    return engine
                },
                contextManager: contextManager
            )

            try await service.acquireContextLease()
            try await service.acquireContextLease()
            let engine = try #require(engines.snapshot().first)
            #expect(await engine.prepareCallCount == 1)

            await contextManager.cleanupResources()
            await service.releaseContextLease()
            #expect(await engine.releaseCallCount == 0)
            await service.releaseContextLease()
            #expect(await engine.releaseCallCount == 1)
        }

        @Test func concurrentLeasesShareOneInFlightModelLoad() async throws {
            let modelManager = try makeModelManager()
            let engines = FunASREngineStore()
            let gate = PrepareGate()
            let contextManager = FunASRNanoContextManager()
            let service = try FunASRNanoTranscriptionService(
                modelManager: modelManager,
                engineFactory: { _ in
                    let engine = StubFunASREngine(text: "shared", prepareGate: gate)
                    engines.append(engine)
                    return engine
                },
                contextManager: contextManager
            )

            let first = Task { try await service.acquireContextLease() }
            await gate.waitUntilWaiting()
            let second = Task { try await service.acquireContextLease() }
            await Task.yield()
            #expect(engines.snapshot().count == 1)

            await gate.resume()
            try await first.value
            try await second.value
            let engine = try #require(engines.snapshot().first)
            #expect(await engine.prepareCallCount == 1)

            await contextManager.cleanupResources()
            await service.releaseContextLease()
            #expect(await engine.releaseCallCount == 0)
            await service.releaseContextLease()
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
            #expect(await engine.receivedHotwords == [nil])
            #expect(await engine.releaseCallCount == 1)
        }

        @Test func transcribesRealGGUFAudioWithHotwordsWhenOptedIn() async throws {
            let audioPath =
                ProcessInfo.processInfo.environment["STET_FUNASR_E2E_AUDIO_PATH"]
                ?? "/private/tmp/stet-funasr-e2e.mp3"
            guard FileManager.default.fileExists(atPath: audioPath) else {
                return
            }

            let service = try FunASRNanoTranscriptionService(
                contextManager: FunASRNanoContextManager()
            )
            let result = try await service.transcribe(
                audioFileAt: URL(fileURLWithPath: audioPath),
                languageCode: nil,
                prompt: "滨海新区, Stet",
                audioDurationSeconds: nil
            )

            #expect(!result.text.isEmpty)
        }

        @Test func maintenanceWaitsForLeasesAndTransientUses() async throws {
            let manager = try makeModelManager()
            let context = FunASRNanoContextManager()
            let engine = StubFunASREngine(text: "idle")
            try await context.acquireLease(files: manager.modelFiles(), engineFactory: { _ in engine })
            #expect(try await !context.performModelMaintenance { Issue.record("Active lease was interrupted") })
            await context.releaseLease()
            try await context.beginModelUse()
            #expect(try await !context.performModelMaintenance { Issue.record("Active transcription was interrupted") })
            await context.endModelUse()
            #expect(try await context.performModelMaintenance {})
            #expect(await engine.releaseCallCount == 1)
        }

        @Test func differentModelCannotReplaceAnActiveLease() async throws {
            let first = try makeModelManager()
            let second = try makeModelManager()
            let context = FunASRNanoContextManager()
            let engine = StubFunASREngine(text: "leased")
            try await context.acquireLease(files: first.modelFiles(), engineFactory: { _ in engine })
            await #expect(throws: FunASRNanoContextError.self) {
                try await context.acquireLease(files: second.modelFiles(), engineFactory: { _ in engine })
            }
            #expect(await engine.prepareCallCount == 1)
            await context.releaseLease()
            await context.cleanupResources()
        }

        @Test(.enabled(if: ANEModelReadiness.supported))
        func runtimeCPUFallbackDisablesReadinessAndReusesLoadedCPUContext() async throws {
            let manager = try makeModelManager()
            let directory = try manager.modelFiles().encoder.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directory.appendingPathComponent(FunASRNanoANEManifest.compiledName),
                withIntermediateDirectories: true)
            try ANEModelReadiness.make(manifestHash: String(repeating: "a", count: 64)).write(in: directory)
            let residentStore = ResidentEncoderStore()
            let context = FunASRNanoContextManager { url in
                let encoder = StubResidentEncoder(modelURL: url)
                residentStore.append(encoder)
                return encoder
            }
            await context.preloadResidentEncoder(in: directory)
            #expect(await context.hasReadyResidentEncoder)
            let engines = FunASREngineStore()
            let service = try FunASRNanoTranscriptionService(
                modelManager: manager,
                engineFactory: { _ in
                    let engine = StubFunASREngine(text: "CPU fallback", backend: "ggml-cpu")
                    engines.append(engine)
                    return engine
                }, contextManager: context)
            try await service.prewarm()
            #expect(ANEModelReadiness.read(in: directory) == nil)
            #expect(ANEModelReadiness.installed(in: directory)?.enabled == false)
            #expect(!(await context.hasReadyResidentEncoder))
            let resident = try #require(residentStore.snapshot().first)
            #expect(resident.releaseCallCount == 1)
            let result = try await service.transcribe(
                audioFileAt: makeAudioFile(), languageCode: nil, prompt: nil, audioDurationSeconds: 1)
            #expect(result.text == "CPU fallback")
            #expect(engines.snapshot().count == 1)
            await context.cleanupResources()
        }

        @Test(.enabled(if: ANEModelReadiness.supported))
        func backgroundResidentCompileNeverBlocksForegroundAndSwitchesToANEOnceReady() async throws {
            let manager = try makeModelManager()
            let directory = try manager.modelFiles().encoder.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directory.appendingPathComponent(FunASRNanoANEManifest.compiledName),
                withIntermediateDirectories: true)
            try ANEModelReadiness.make(manifestHash: String(repeating: "c", count: 64)).write(in: directory)

            let compileGate = PrepareGate()
            let residentStore = ResidentEncoderStore()
            let context = FunASRNanoContextManager { url in
                await compileGate.wait()
                let encoder = StubResidentEncoder(modelURL: url)
                residentStore.append(encoder)
                return encoder
            }
            let engines = FunASREngineStore()
            let service = try FunASRNanoTranscriptionService(
                modelManager: manager,
                residentEngineFactory: { files, resident in
                    let backend = files.encoder.pathExtension == "mlmodelc" ? "coreml-cpu-and-ne" : "ggml-cpu"
                    let engine = StubFunASREngine(
                        text: backend,
                        backend: backend,
                        encoderExtension: files.encoder.pathExtension,
                        hadResidentEncoder: resident != nil
                    )
                    engines.append(engine)
                    return engine
                },
                contextManager: context
            )

            await context.scheduleResidentEncoderPreload(in: directory)
            await compileGate.waitUntilWaiting()

            try await service.prewarm()
            let firstResult = try await service.transcribe(
                audioFileAt: makeAudioFile(),
                languageCode: nil,
                prompt: nil,
                audioDurationSeconds: 1.5
            )
            #expect(firstResult.text == "ggml-cpu")
            #expect(ANEModelReadiness.read(in: directory) != nil)
            let firstEngine = try #require(engines.snapshot().first)
            #expect(await firstEngine.encoderExtension == "gguf")
            #expect(!(await firstEngine.hadResidentEncoder))

            await compileGate.resume()
            try #require(await TestSupport.eventuallyAsync { await context.hasReadyResidentEncoder })

            try await service.prewarm()
            let secondResult = try await service.transcribe(
                audioFileAt: makeAudioFile(),
                languageCode: nil,
                prompt: nil,
                audioDurationSeconds: 1.5
            )
            #expect(secondResult.text == "coreml-cpu-and-ne")
            let secondEngine = try #require(engines.snapshot().last)
            #expect(await secondEngine.encoderExtension == "mlmodelc")
            #expect(await secondEngine.hadResidentEncoder)

            // Unloading Qwen3 keeps the resident ANE encoder warm across sessions.
            await context.cleanupResources()
            #expect(await secondEngine.releaseCallCount == 1)
            #expect(await context.hasReadyResidentEncoder)
            let resident = try #require(residentStore.snapshot().first)
            #expect(resident.releaseCallCount == 0)

            // Subsequent session reuses the same resident ANE encoder without reloading it.
            try await service.prewarm()
            #expect(residentStore.snapshot().count == 1)

            // Maintenance unloads both Qwen3 and the resident ANE encoder once idle.
            #expect(try await context.performModelMaintenance {})
            #expect(!(await context.hasReadyResidentEncoder))
            #expect(resident.releaseCallCount == 1)
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
        private let prepareGate: PrepareGate?
        private let backend: String
        let encoderExtension: String
        let hadResidentEncoder: Bool
        private(set) var prepareCallCount = 0
        private(set) var transcribeCallCount = 0
        private(set) var releaseCallCount = 0
        private(set) var receivedHotwords: [String?] = []

        init(
            text: String,
            prepareGate: PrepareGate? = nil,
            backend: String = "unknown",
            encoderExtension: String = "gguf",
            hadResidentEncoder: Bool = false
        ) {
            self.backend = backend
            self.text = text
            self.prepareGate = prepareGate
            self.encoderExtension = encoderExtension
            self.hadResidentEncoder = hadResidentEncoder
        }

        func encoderBackend() async -> String { backend }

        func prepare() async throws {
            prepareCallCount += 1
            await prepareGate?.wait()
        }

        func transcribe(audioFileURL _: URL, hotwords: String?) async throws -> String {
            transcribeCallCount += 1
            receivedHotwords.append(hotwords)
            return text
        }

        func releaseResources() async {
            releaseCallCount += 1
        }
    }

    private actor PrepareGate {
        private var continuation: CheckedContinuation<Void, Never>?
        private var waiting = false

        func wait() async {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                waiting = true
            }
        }

        func waitUntilWaiting() async {
            while !waiting {
                await Task.yield()
            }
        }

        func resume() {
            continuation?.resume()
            continuation = nil
            waiting = false
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

    private nonisolated final class StubResidentEncoder: FunASRNanoResidentEncoding, @unchecked Sendable {
        let modelURL: URL
        private let lock = NSLock()
        private var releases = 0
        var releaseCallCount: Int { lock.withLock { releases } }

        init(modelURL: URL) {
            self.modelURL = modelURL
        }

        func warmup() throws {}

        func releaseResources() {
            lock.withLock { releases += 1 }
        }
    }

    private nonisolated final class ResidentEncoderStore: @unchecked Sendable {
        private let lock = NSLock()
        private var encoders: [StubResidentEncoder] = []

        func append(_ encoder: StubResidentEncoder) {
            lock.withLock { encoders.append(encoder) }
        }

        func snapshot() -> [StubResidentEncoder] {
            lock.withLock { encoders }
        }
    }
#endif
