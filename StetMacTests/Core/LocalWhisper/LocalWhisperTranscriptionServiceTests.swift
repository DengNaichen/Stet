#if os(macOS)
    import Foundation
    import Testing

    @testable import Stet

    @MainActor
    @Suite("Local Whisper Transcription Service", .serialized)
    struct LocalWhisperTranscriptionServiceTests {
        @Test func transcribeReusesEngineLoadedInContextManager() async throws {
            let modelsDirectoryURL = TestSupport.temporaryDirectoryURL()
            try FileManager.default.createDirectory(at: modelsDirectoryURL, withIntermediateDirectories: true)
            let modelURL = modelsDirectoryURL.appendingPathComponent(LocalWhisperModelDescriptor.default.fileName)
            try Data("model".utf8).write(to: modelURL)
            let audioURL = try makeStubWaveFile()

            let createdEngines = CreatedEngines()
            let manager = LocalWhisperContextManager()
            try await manager.loadModel(modelURL: modelURL) { url in
                let engine = StubLocalWhisperEngine()
                createdEngines.append(engine)
                return engine
            }

            let modelManager = LocalWhisperModelManager(
                configuration: UserDefaultsModelStorage(defaults: TestSupport.makeUserDefaults()),
                modelsDirectoryProvider: { modelsDirectoryURL },
                runtimeAvailableProvider: { true }
            )
            let service = try LocalWhisperTranscriptionService(
                modelManager: modelManager,
                engineFactory: { _ in
                    let engine = StubLocalWhisperEngine()
                    createdEngines.append(engine)
                    return engine
                },
                contextManagerProvider: { manager }
            )

            _ = try await service.transcribe(
                audioFileAt: audioURL,
                languageCode: nil,
                prompt: nil,
                audioDurationSeconds: nil
            )

            let engines = createdEngines.snapshot()
            #expect(engines.count == 1)
            let reusedEngine = try #require(engines.first)
            #expect(await reusedEngine.transcribeCallCount == 1)
            #expect(await reusedEngine.releaseCallCount == 0)
            #expect(manager.isModelLoaded)
        }

        @Test func transcribeWithoutLoadedModelUsesTransientEngineAndReleasesIt() async throws {
            let modelsDirectoryURL = TestSupport.temporaryDirectoryURL()
            try FileManager.default.createDirectory(at: modelsDirectoryURL, withIntermediateDirectories: true)
            let modelURL = modelsDirectoryURL.appendingPathComponent(LocalWhisperModelDescriptor.default.fileName)
            try Data("model".utf8).write(to: modelURL)
            let audioURL = try makeStubWaveFile()

            let createdEngines = CreatedEngines()
            let manager = LocalWhisperContextManager()
            let modelManager = LocalWhisperModelManager(
                configuration: UserDefaultsModelStorage(defaults: TestSupport.makeUserDefaults()),
                modelsDirectoryProvider: { modelsDirectoryURL },
                runtimeAvailableProvider: { true }
            )
            let service = try LocalWhisperTranscriptionService(
                modelManager: modelManager,
                engineFactory: { _ in
                    let engine = StubLocalWhisperEngine()
                    createdEngines.append(engine)
                    return engine
                },
                contextManagerProvider: { manager }
            )

            _ = try await service.transcribe(
                audioFileAt: audioURL,
                languageCode: nil,
                prompt: nil,
                audioDurationSeconds: nil
            )

            let engines = createdEngines.snapshot()
            #expect(engines.count == 1)
            let transientEngine = try #require(engines.first)
            #expect(await transientEngine.transcribeCallCount == 1)
            #expect(await transientEngine.releaseCallCount == 1)
            #expect(!manager.isModelLoaded)
        }

        @Test func prewarmLoadsEngineIntoContextManager() async throws {
            let modelsDirectoryURL = TestSupport.temporaryDirectoryURL()
            try FileManager.default.createDirectory(at: modelsDirectoryURL, withIntermediateDirectories: true)
            let modelURL = modelsDirectoryURL.appendingPathComponent(LocalWhisperModelDescriptor.default.fileName)
            try Data("model".utf8).write(to: modelURL)

            let createdEngines = CreatedEngines()
            let manager = LocalWhisperContextManager()
            let modelManager = LocalWhisperModelManager(
                configuration: UserDefaultsModelStorage(defaults: TestSupport.makeUserDefaults()),
                modelsDirectoryProvider: { modelsDirectoryURL },
                runtimeAvailableProvider: { true }
            )
            let service = try LocalWhisperTranscriptionService(
                modelManager: modelManager,
                engineFactory: { _ in
                    let engine = StubLocalWhisperEngine()
                    createdEngines.append(engine)
                    return engine
                },
                contextManagerProvider: { manager }
            )

            try await service.prewarm()

            let engines = createdEngines.snapshot()
            #expect(engines.count == 1)
            #expect(manager.isModelLoaded)
            #expect(manager.loadedModelPath == modelURL.standardizedFileURL.path)
        }

        @Test func cleanupResourcesReleasesLoadedEngine() async throws {
            let modelsDirectoryURL = TestSupport.temporaryDirectoryURL()
            try FileManager.default.createDirectory(at: modelsDirectoryURL, withIntermediateDirectories: true)
            let modelURL = modelsDirectoryURL.appendingPathComponent(LocalWhisperModelDescriptor.default.fileName)
            try Data("model".utf8).write(to: modelURL)

            let manager = LocalWhisperContextManager()
            let createdEngines = CreatedEngines()
            try await manager.loadModel(modelURL: modelURL) { _ in
                let engine = StubLocalWhisperEngine()
                createdEngines.append(engine)
                return engine
            }

            #expect(manager.isModelLoaded)
            await manager.cleanupResources()

            #expect(!manager.isModelLoaded)
            #expect(manager.loadedModelPath == nil)
            let engines = createdEngines.snapshot()
            let releasedEngine = try #require(engines.first)
            #expect(await releasedEngine.releaseCallCount == 1)
        }

        @Test func loadModelIsIdempotentWhileEngineLoaded() async throws {
            let modelsDirectoryURL = TestSupport.temporaryDirectoryURL()
            try FileManager.default.createDirectory(at: modelsDirectoryURL, withIntermediateDirectories: true)
            let modelURL = modelsDirectoryURL.appendingPathComponent(LocalWhisperModelDescriptor.default.fileName)
            try Data("model".utf8).write(to: modelURL)

            let manager = LocalWhisperContextManager()
            let createdEngines = CreatedEngines()
            try await manager.loadModel(modelURL: modelURL) { _ in
                let engine = StubLocalWhisperEngine()
                createdEngines.append(engine)
                return engine
            }
            try await manager.loadModel(modelURL: modelURL) { _ in
                let engine = StubLocalWhisperEngine()
                createdEngines.append(engine)
                return engine
            }

            let engines = createdEngines.snapshot()
            #expect(engines.count == 1)
        }

        // Build a minimal RIFF/WAVE container so AVAudioFile can read it during transcribe.
        private func makeStubWaveFile() throws -> URL {
            let url = TestSupport.temporaryFileURL("local-whisper-stub-audio", ext: "wav")
            // 16-bit mono PCM at 16 kHz with 32 zero samples (~2 ms of silence).
            let sampleRate: UInt32 = 16000
            let bitsPerSample: UInt16 = 16
            let channels: UInt16 = 1
            let sampleCount = 32
            let dataByteCount = sampleCount * Int(bitsPerSample / 8)
            let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample / 8)
            let blockAlign = channels * (bitsPerSample / 8)

            var bytes = Data()
            bytes.append(contentsOf: "RIFF".utf8)
            bytes.appendLittleEndian(UInt32(36 + dataByteCount))
            bytes.append(contentsOf: "WAVE".utf8)
            bytes.append(contentsOf: "fmt ".utf8)
            bytes.appendLittleEndian(UInt32(16))
            bytes.appendLittleEndian(UInt16(1))
            bytes.appendLittleEndian(channels)
            bytes.appendLittleEndian(sampleRate)
            bytes.appendLittleEndian(byteRate)
            bytes.appendLittleEndian(blockAlign)
            bytes.appendLittleEndian(bitsPerSample)
            bytes.append(contentsOf: "data".utf8)
            bytes.appendLittleEndian(UInt32(dataByteCount))
            bytes.append(Data(repeating: 0, count: dataByteCount))

            try bytes.write(to: url)
            return url
        }
    }

    private actor StubLocalWhisperEngine: LocalWhisperEngine {
        private(set) var transcribeCallCount = 0
        private(set) var releaseCallCount = 0
        private(set) var prewarmCallCount = 0

        func prewarm() async throws {
            prewarmCallCount += 1
        }

        func transcribe(
            samples _: [Float],
            languageCode _: String?,
            prompt _: String?
        ) async throws -> TranscriptionResult {
            transcribeCallCount += 1
            return TranscriptionResult(text: "warm", languageCode: nil)
        }

        func releaseResources() async {
            releaseCallCount += 1
        }
    }

    private final class CreatedEngines: @unchecked Sendable {
        private let lock = NSLock()
        private var engines: [StubLocalWhisperEngine] = []

        func append(_ engine: StubLocalWhisperEngine) {
            lock.lock()
            defer { lock.unlock() }
            engines.append(engine)
        }

        func snapshot() -> [StubLocalWhisperEngine] {
            lock.lock()
            defer { lock.unlock() }
            return engines
        }
    }

    private extension Data {
        mutating func appendLittleEndian(_ value: UInt16) {
            var le = value.littleEndian
            Swift.withUnsafeBytes(of: &le) { append(contentsOf: $0) }
        }

        mutating func appendLittleEndian(_ value: UInt32) {
            var le = value.littleEndian
            Swift.withUnsafeBytes(of: &le) { append(contentsOf: $0) }
        }
    }
#endif
