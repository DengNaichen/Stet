#if os(macOS)
    import Foundation
    import StetASR
    import StetCore
    import Testing

    @testable import Stet

    struct FunASRNanoModelManagerTests {
        @Test func installDownloadsEveryMissingComponent() async throws {
            let modelsDirectory = TestSupport.temporaryDirectoryURL()
            let stagingDirectory = TestSupport.temporaryDirectoryURL()
            try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)

            let stagedFiles = try FunASRNanoModelAsset.allCases.enumerated().map { index, _ in
                let url = stagingDirectory.appendingPathComponent("asset-\(index)")
                try Data("asset-\(index)".utf8).write(to: url)
                return url
            }
            let queue = FunASRDownloadQueue(stagedFiles: stagedFiles)
            let manager = FunASRNanoModelManager(
                modelsDirectoryProvider: { modelsDirectory },
                downloadProvider: { url in try await queue.next(for: url) }, prepareEncoder: Self.prepareFixture
            )

            try await manager.installDefaultModel()

            #expect(manager.isModelDownloaded())
            #expect(
                try manager.resolvedModelFiles().allFiles.map(\.lastPathComponent) == [
                    FunASRNanoANEManifest.compiledName,
                    "qwen3-0.6b-q4km.gguf",
                    "fsmn-vad.gguf",
                ])
            #expect(
                await queue.requestedURLs
                    == FunASRNanoModelAsset.allCases.map { ModelDownloadMirror.candidates(for: $0.downloadURL)[0] })
        }

        @Test func installSkipsComponentsAlreadyPresent() async throws {
            let modelsDirectory = TestSupport.temporaryDirectoryURL()
            try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
            let manager = FunASRNanoModelManager(
                modelsDirectoryProvider: { modelsDirectory },
                downloadProvider: { _ in throw TestError.expected }, prepareEncoder: Self.prepareFixture
            )
            let files = try manager.modelFiles()
            for file in [files.languageModel, files.voiceActivityDetector] {
                try Data("model".utf8).write(to: file)
            }

            try await manager.installDefaultModel()

            #expect(manager.isModelDownloaded())
        }

        private static func prepareFixture(in directory: URL) throws {
            try FileManager.default.createDirectory(
                at: directory.appendingPathComponent(FunASRNanoANEManifest.compiledName),
                withIntermediateDirectories: true)
            try ANEModelReadiness.make(manifestHash: String(repeating: "a", count: 64)).write(in: directory)
        }

        @Test func legacyCPUEncoderCannotSatisfyReadiness() throws {
            let directory = TestSupport.temporaryDirectoryURL()
            defer { try? FileManager.default.removeItem(at: directory) }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let manager = FunASRNanoModelManager(modelsDirectoryProvider: { directory })
            let files = try manager.modelFiles()
            let legacy = directory.appendingPathComponent("funasr-encoder-f16.gguf")
            for file in [legacy, files.languageModel, files.voiceActivityDetector] {
                try Data("fixture".utf8).write(to: file)
            }
            #expect(!manager.isModelDownloaded())
            #expect(throws: ANEModelInstallError.self) { try manager.resolvedModelFiles() }
            try FileManager.default.removeItem(at: legacy)
            try Self.prepareFixture(in: directory)
            #expect(manager.isModelDownloaded())
            #expect(try manager.resolvedModelFiles().encoder == files.encoder)
        }

        @Test func invalidHTTPResponseDoesNotInstallComponent() async throws {
            let modelsDirectory = TestSupport.temporaryDirectoryURL()
            let stagedFile = TestSupport.temporaryFileURL("funasr-invalid-download", ext: "gguf")
            try Data("invalid".utf8).write(to: stagedFile)
            let manager = FunASRNanoModelManager(
                modelsDirectoryProvider: { modelsDirectory },
                downloadProvider: { url in
                    let response = HTTPURLResponse(
                        url: url,
                        statusCode: 503,
                        httpVersion: nil,
                        headerFields: nil
                    )!
                    return (stagedFile, response)
                }
            )

            await #expect(throws: FunASRNanoModelError.self) {
                try await manager.installDefaultModel()
            }
            #expect(!manager.isModelDownloaded())
            #expect(!FileManager.default.fileExists(atPath: stagedFile.path))
        }
    }

    private actor FunASRDownloadQueue {
        private var stagedFiles: [URL]
        private(set) var requestedURLs: [URL] = []

        init(stagedFiles: [URL]) {
            self.stagedFiles = stagedFiles
        }

        func next(for requestedURL: URL) throws -> (URL, URLResponse) {
            requestedURLs.append(requestedURL)
            guard !stagedFiles.isEmpty else { throw TestError.expected }
            let response = HTTPURLResponse(
                url: requestedURL,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (stagedFiles.removeFirst(), response)
        }
    }
#endif
