#if os(macOS)
    import Foundation
    import StetASR
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
                downloadProvider: { url in try await queue.next(for: url) }
            )

            try await manager.installDefaultModel()

            #expect(manager.isModelDownloaded())
            #expect(
                try manager.resolvedModelFiles().allFiles.map(\.lastPathComponent) == [
                    "funasr-encoder-f16.gguf",
                    "qwen3-0.6b-q4km.gguf",
                    "fsmn-vad.gguf",
                ])
            #expect(await queue.requestedURLs == FunASRNanoModelAsset.allCases.map(\.downloadURL))
        }

        @Test func installSkipsComponentsAlreadyPresent() async throws {
            let modelsDirectory = TestSupport.temporaryDirectoryURL()
            try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
            let manager = FunASRNanoModelManager(
                modelsDirectoryProvider: { modelsDirectory },
                downloadProvider: { _ in throw TestError.expected }
            )
            let files = try manager.modelFiles()
            for file in files.allFiles {
                try Data("model".utf8).write(to: file)
            }

            try await manager.installDefaultModel()

            #expect(manager.isModelDownloaded())
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
