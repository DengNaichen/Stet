#if os(macOS)
    import Foundation
    import Testing

    @testable import Stet

    @Suite("Local Whisper Transcription Service", .serialized)
    struct LocalWhisperTranscriptionServiceTests {
        @Test func acquiredEngineReusesSingleInstancePerModelPath() throws {
            LocalWhisperEngineFactory.invalidateSharedEngines()
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
            LocalWhisperEngineFactory.invalidateSharedEngines()
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

        @Test func releasedLeaseRemovesSharedEngineWhenSessionEnds() throws {
            LocalWhisperEngineFactory.invalidateSharedEngines()
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

        @Test func invalidatingSharedEnginesAllowsRecreation() throws {
            LocalWhisperEngineFactory.invalidateSharedEngines()
            let modelURL = TestSupport.temporaryFileURL("local-whisper-model-invalidate", ext: "bin")
            let createdEngines = CreatedEngines()

            let firstLease = try LocalWhisperEngineFactory.acquireEngine(modelURL: modelURL) {
                let engine = StubLocalWhisperEngine()
                createdEngines.append(engine)
                return engine
            }
            _ = firstLease

            LocalWhisperEngineFactory.invalidateSharedEngines()

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

        @Test func serviceInitializationDefersEngineCreationUntilFirstUse() async throws {
            LocalWhisperEngineFactory.invalidateSharedEngines()
            let modelsDirectoryURL = TestSupport.temporaryDirectoryURL()
            try FileManager.default.createDirectory(at: modelsDirectoryURL, withIntermediateDirectories: true)
            let modelURL = modelsDirectoryURL.appendingPathComponent(LocalWhisperModelDescriptor.default.fileName)
            try Data("model".utf8).write(to: modelURL)
            let createdEngines = CreatedEngines()

            let service = try LocalWhisperTranscriptionService(
                modelManager: LocalWhisperModelManager(
                    modelsDirectoryProvider: { modelsDirectoryURL },
                    runtimeAvailableProvider: { true },
                    customPathProvider: { nil }
                ),
                engineFactory: { url in
                    try LocalWhisperEngineFactory.acquireEngine(modelURL: url) {
                        let engine = StubLocalWhisperEngine()
                        createdEngines.append(engine)
                        return engine
                    }
                }
            )

            #expect(createdEngines.snapshot().isEmpty)

            try await service.prewarm()

            let created = createdEngines.snapshot()
            #expect(created.count == 1)
        }

        @Test func activeLeaseKeepsSharedEngineAliveUntilLastRelease() throws {
            LocalWhisperEngineFactory.invalidateSharedEngines()
            let modelURL = TestSupport.temporaryFileURL("local-whisper-model-active-lease", ext: "bin")
            let createdEngines = CreatedEngines()

            let firstLease = try LocalWhisperEngineFactory.acquireEngine(modelURL: modelURL) {
                let engine = StubLocalWhisperEngine()
                createdEngines.append(engine)
                return engine
            }

            do {
                let secondLease = try LocalWhisperEngineFactory.acquireEngine(modelURL: modelURL) {
                    let engine = StubLocalWhisperEngine()
                    createdEngines.append(engine)
                    return engine
                }
                _ = secondLease
            }

            let reusedLease = try LocalWhisperEngineFactory.acquireEngine(modelURL: modelURL) {
                let engine = StubLocalWhisperEngine()
                createdEngines.append(engine)
                return engine
            }

            let created = createdEngines.snapshot()
            let firstEngine = try #require(firstLease.engine as? StubLocalWhisperEngine)
            let reusedEngine = try #require(reusedLease.engine as? StubLocalWhisperEngine)
            #expect(created.count == 1)
            #expect(firstEngine === created[0])
            #expect(reusedEngine === created[0])
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
