#if os(macOS)
    import Foundation
    import Testing

    @testable import Stet

    @MainActor
    @Suite("Local Whisper Warmup Coordinator")
    struct LocalWhisperWarmupCoordinatorTests {
        @Test func warmupReusesSharedServiceForSameModelPath() async throws {
            let modelsDirectoryURL = TestSupport.temporaryDirectoryURL()
            try FileManager.default.createDirectory(at: modelsDirectoryURL, withIntermediateDirectories: true)

            let modelURL = modelsDirectoryURL.appendingPathComponent(LocalWhisperModelDescriptor.default.fileName)
            try Data("model".utf8).write(to: modelURL)

            let sampleURL = modelsDirectoryURL.appendingPathComponent("sample.wav")
            try Data("sample".utf8).write(to: sampleURL)

            let createdServices = CreatedWarmServices()
            let coordinator = LocalWhisperWarmupCoordinator(
                modelManager: LocalWhisperModelManager(
                    modelsDirectoryProvider: { modelsDirectoryURL },
                    runtimeAvailableProvider: { true },
                    customPathProvider: { nil }
                ),
                startupWarmupDelay: 60,
                keepAliveWarmupInterval: 60,
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
            #expect(services.count == 1)
            #expect(services[0].transcribeCallCount == 2)
        }

        @Test func warmupReplacesSharedServiceWhenModelPathChanges() async throws {
            let modelsDirectoryURL = TestSupport.temporaryDirectoryURL()
            try FileManager.default.createDirectory(at: modelsDirectoryURL, withIntermediateDirectories: true)

            let firstModelURL = modelsDirectoryURL.appendingPathComponent("first-model.bin")
            try Data("first".utf8).write(to: firstModelURL)

            let secondModelURL = modelsDirectoryURL.appendingPathComponent("second-model.bin")
            try Data("second".utf8).write(to: secondModelURL)

            let sampleURL = modelsDirectoryURL.appendingPathComponent("sample.wav")
            try Data("sample".utf8).write(to: sampleURL)

            let selectedModelPath = LockedPath(firstModelURL.path)
            let createdServices = CreatedWarmServices()
            let coordinator = LocalWhisperWarmupCoordinator(
                modelManager: LocalWhisperModelManager(
                    modelsDirectoryProvider: { modelsDirectoryURL },
                    runtimeAvailableProvider: { true },
                    customPathProvider: { selectedModelPath.value }
                ),
                startupWarmupDelay: 60,
                keepAliveWarmupInterval: 60,
                sampleURLProvider: { sampleURL },
                serviceFactory: { _ in
                    let service = StubWarmupTranscriptionService()
                    createdServices.append(service)
                    return service
                }
            )

            try await coordinator.warmup()
            selectedModelPath.set(secondModelURL.path)
            try await coordinator.warmup()

            let services = createdServices.snapshot()
            #expect(services.count == 2)
            #expect(services[0].transcribeCallCount == 1)
            #expect(services[1].transcribeCallCount == 1)
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

    private final class LockedPath: @unchecked Sendable {
        private var path: String?
        private let lock = NSLock()

        init(_ path: String?) {
            self.path = path
        }

        var value: String? {
            lock.lock()
            defer { lock.unlock() }
            return path
        }

        func set(_ path: String?) {
            lock.lock()
            defer { lock.unlock() }
            self.path = path
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
        ) async throws -> String {
            lock.lock()
            defer { lock.unlock() }
            transcribeCallCount += 1
            return "warm"
        }
    }
#endif
