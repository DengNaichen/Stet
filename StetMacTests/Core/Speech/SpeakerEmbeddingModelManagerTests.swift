#if os(macOS)
    import Foundation
    import StetASR
    import Testing

    @testable import Stet

    @Suite("Speaker Embedding Model Loading")
    struct SpeakerEmbeddingModelManagerTests {
        @Test func concurrentRequestsShareOneLoadAndFailureCanRetry() async throws {
            let loader = SuspendedSpeakerModelLoader()
            let manager = SpeakerEmbeddingModelManager(loadRecognizer: { try await loader.load() })
            let first = Task { try await manager.recognizer() }
            try #require(await TestSupport.eventuallyAsync { await loader.attempts == 1 })
            let second = Task { try await manager.recognizer() }
            // Keep the first load suspended while the second caller enters the actor.
            try await Task.sleep(for: .milliseconds(50))
            await loader.open()
            _ = await first.result
            _ = await second.result
            #expect(await loader.attempts == 1)
            await #expect(throws: SpeakerEmbeddingRecognizerError.modelNotFound) {
                try await manager.recognizer()
            }
            #expect(await loader.attempts == 2)
        }
    }

    private actor SuspendedSpeakerModelLoader {
        private(set) var attempts = 0
        private var isOpen = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func load() async throws -> SpeakerEmbeddingRecognizer {
            attempts += 1
            if !isOpen {
                await withCheckedContinuation { waiters.append($0) }
            }
            throw SpeakerEmbeddingRecognizerError.modelNotFound
        }

        func open() {
            isOpen = true
            let pending = waiters
            waiters.removeAll()
            pending.forEach { $0.resume() }
        }
    }
#endif
