#if os(macOS)
    import Foundation
    import Testing

    @testable import Stet

    @MainActor
    @Suite("Local Whisper Warmup Coordinator")
    struct LocalWhisperWarmupCoordinatorTests {
        @Test func warmupCreatesFreshServiceEachTime() async throws {
            let modelsDirectoryURL = TestSupport.temporaryDirectoryURL()
            try FileManager.default.createDirectory(at: modelsDirectoryURL, withIntermediateDirectories: true)

            let modelURL = modelsDirectoryURL.appendingPathComponent(LocalWhisperModelDescriptor.default.fileName)
            try Data("model".utf8).write(to: modelURL)

            let sampleURL = modelsDirectoryURL.appendingPathComponent("sample.wav")
            try Data("sample".utf8).write(to: sampleURL)

            let createdServices = CreatedWarmServices()
            let coordinator = LocalWhisperWarmupCoordinator(
                modelManager: LocalWhisperModelManager(
                    configuration: UserDefaultsModelStorage(defaults: TestSupport.makeUserDefaults()),
                    modelsDirectoryProvider: { modelsDirectoryURL },
                    runtimeAvailableProvider: { true }
                ),
                startupWarmupDelay: 60,
                sampleURLProvider: { sampleURL },
                serviceFactory: { _ in
                    let service = StubWarmupTranscriptionService()
                    createdServices.append(service)
                    return service
                }
            )

            try await coordinator.warmup()
            try await coordinator.warmup()

            let services = createdServices.snapshot()
            #expect(services.count == 2)
            #expect(services[0].transcribeCallCount == 1)
            #expect(services[1].transcribeCallCount == 1)
        }

        @Test func warmupSkipsServiceCreationWhenModelIsMissing() async throws {
            let modelsDirectoryURL = TestSupport.temporaryDirectoryURL()
            try FileManager.default.createDirectory(at: modelsDirectoryURL, withIntermediateDirectories: true)

            let sampleURL = modelsDirectoryURL.appendingPathComponent("sample.wav")
            try Data("sample".utf8).write(to: sampleURL)

            let createdServices = CreatedWarmServices()
            let coordinator = LocalWhisperWarmupCoordinator(
                modelManager: LocalWhisperModelManager(
                    configuration: UserDefaultsModelStorage(defaults: TestSupport.makeUserDefaults()),
                    modelsDirectoryProvider: { modelsDirectoryURL },
                    runtimeAvailableProvider: { true }
                ),
                startupWarmupDelay: 60,
                sampleURLProvider: { sampleURL },
                serviceFactory: { _ in
                    let service = StubWarmupTranscriptionService()
                    createdServices.append(service)
                    return service
                }
            )

            try await coordinator.warmup()

            let services = createdServices.snapshot()
            #expect(services.isEmpty)
        }
    }

    private final class CreatedWarmServices: @unchecked Sendable {
        private var services: [StubWarmupTranscriptionService] = []
        private let lock = NSLock()

        func append(_ service: StubWarmupTranscriptionService) {
            lock.lock()
            defer { lock.unlock() }
            services.append(service)
        }

        func snapshot() -> [StubWarmupTranscriptionService] {
            lock.lock()
            defer { lock.unlock() }
            return services
        }
    }

    private final class StubWarmupTranscriptionService: @unchecked Sendable, AudioFileTranscriptionService {
        private let lock = NSLock()
        private(set) var transcribeCallCount = 0

        func prewarm() async throws {}

        func transcribe(
            audioFileAt _: URL,
            languageCode _: String?,
            prompt _: String?,
            audioDurationSeconds _: TimeInterval?
        ) async throws -> TranscriptionResult {
            lock.lock()
            defer { lock.unlock() }
            transcribeCallCount += 1
            return TranscriptionResult(text: "warm", languageCode: nil)
        }
    }
#endif
