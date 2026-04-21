#if os(macOS)
    import Foundation
    import Testing

    @testable import Stet

    @Suite("Local Whisper Transcription Service")
    struct LocalWhisperTranscriptionServiceTests {
        @Test func acquiredEngineReusesSingleInstancePerModelPath() throws {
            let modelURL = TestSupport.temporaryFileURL("local-whisper-model", ext: "bin")
            let createdEngines = CreatedEngines()

            let firstLease = try LocalWhisperEngineFactory.acquireEngine(modelURL: modelURL) {
                let engine = StubLocalWhisperEngine()
                createdEngines.append(engine)
                return engine
            }
            let secondLease = try LocalWhisperEngineFactory.acquireEngine(modelURL: modelURL) {
                let engine = StubLocalWhisperEngine()
                createdEngines.append(engine)
                return engine
            }

            let created = createdEngines.snapshot()
            let firstEngine = try #require(firstLease.engine as? StubLocalWhisperEngine)
            let secondEngine = try #require(secondLease.engine as? StubLocalWhisperEngine)
            #expect(created.count == 1)
            #expect(firstEngine === created[0])
            #expect(secondEngine === created[0])
        }

        @Test func acquiredEngineSeparatesDifferentModelPaths() throws {
            let firstModelURL = TestSupport.temporaryFileURL("local-whisper-model-a", ext: "bin")
            let secondModelURL = TestSupport.temporaryFileURL("local-whisper-model-b", ext: "bin")
            let createdEngines = CreatedEngines()

            let firstLease = try LocalWhisperEngineFactory.acquireEngine(modelURL: firstModelURL) {
                let engine = StubLocalWhisperEngine()
                createdEngines.append(engine)
                return engine
            }
            let secondLease = try LocalWhisperEngineFactory.acquireEngine(modelURL: secondModelURL) {
                let engine = StubLocalWhisperEngine()
                createdEngines.append(engine)
                return engine
            }

            let created = createdEngines.snapshot()
            let firstEngine = try #require(firstLease.engine as? StubLocalWhisperEngine)
            let secondEngine = try #require(secondLease.engine as? StubLocalWhisperEngine)
            #expect(created.count == 2)
            #expect(firstEngine === created[0])
            #expect(secondEngine === created[1])
            #expect(firstEngine !== secondEngine)
        }

        @Test func releasedLeaseAllowsEngineToBeRecreated() throws {
            let modelURL = TestSupport.temporaryFileURL("local-whisper-model-release", ext: "bin")
            let createdEngines = CreatedEngines()

            do {
                let lease = try LocalWhisperEngineFactory.acquireEngine(modelURL: modelURL) {
                    let engine = StubLocalWhisperEngine()
                    createdEngines.append(engine)
                    return engine
                }
                _ = lease
            }

            let recreatedLease = try LocalWhisperEngineFactory.acquireEngine(modelURL: modelURL) {
                let engine = StubLocalWhisperEngine()
                createdEngines.append(engine)
                return engine
            }

            let created = createdEngines.snapshot()
            let recreatedEngine = try #require(recreatedLease.engine as? StubLocalWhisperEngine)
            #expect(created.count == 2)
            #expect(recreatedEngine === created[1])
        }
    }

    private final class StubLocalWhisperEngine: LocalWhisperEngine {
        func prewarm() async throws {}

        func transcribe(
            samples _: [Float],
            languageCode _: String?,
            prompt _: String?
        ) async throws -> String {
            ""
        }
    }

    private final class CreatedEngines {
        private var engines: [StubLocalWhisperEngine] = []

        func append(_ engine: StubLocalWhisperEngine) {
            engines.append(engine)
        }

        func snapshot() -> [StubLocalWhisperEngine] {
            engines
        }
    }
#endif
