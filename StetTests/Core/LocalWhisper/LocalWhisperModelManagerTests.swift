#if os(macOS)
    import Foundation
    import Testing

    @testable import Stet

    struct LocalWhisperModelManagerTests {
        @Test func installDefaultModelDownloadsOnlyModel() async throws {
            let modelsDirectoryURL = TestSupport.temporaryDirectoryURL()
            try FileManager.default.createDirectory(at: modelsDirectoryURL, withIntermediateDirectories: true)

            let downloadedModelURL = modelsDirectoryURL.appendingPathComponent("downloaded-model.bin")
            try Data("model".utf8).write(to: downloadedModelURL)

            let downloadQueue = DownloadQueue(urls: [downloadedModelURL])
            let manager = LocalWhisperModelManager(
                modelsDirectoryProvider: { modelsDirectoryURL },
                runtimeAvailableProvider: { true },
                customPathProvider: { nil },
                downloadProvider: { url in
                    try await downloadQueue.next(requestedURL: url)
                },
                archiveExtractor: { _, _ in
                    Issue.record("archiveExtractor should not run while downloading only the model")
                }
            )

            try await manager.installDefaultModel()

            #expect(try manager.defaultModelReady())
            #expect(!(try manager.defaultEncoderReady()))
            #expect(await downloadQueue.requestedURLs == [LocalWhisperModelManager.defaultModelDownloadURL])
        }

        @Test func installDefaultEncoderDownloadsAndExtractsEncoder() async throws {
            let modelsDirectoryURL = TestSupport.temporaryDirectoryURL()
            try FileManager.default.createDirectory(at: modelsDirectoryURL, withIntermediateDirectories: true)

            let modelURL = modelsDirectoryURL.appendingPathComponent(LocalWhisperModelDescriptor.default.fileName)
            try Data("model".utf8).write(to: modelURL)

            let downloadedArchiveURL = modelsDirectoryURL.appendingPathComponent("downloaded-encoder.zip")
            try Data("archive".utf8).write(to: downloadedArchiveURL)

            let downloadQueue = DownloadQueue(urls: [downloadedArchiveURL])
            let manager = LocalWhisperModelManager(
                modelsDirectoryProvider: { modelsDirectoryURL },
                runtimeAvailableProvider: { true },
                customPathProvider: { nil },
                downloadProvider: { url in
                    try await downloadQueue.next(requestedURL: url)
                },
                archiveExtractor: { _, destinationDirectoryURL in
                    let encoderDirectoryURL = destinationDirectoryURL.appendingPathComponent(
                        LocalWhisperModelManager.defaultEncoderDirectoryName,
                        isDirectory: true
                    )
                    try FileManager.default.createDirectory(at: encoderDirectoryURL, withIntermediateDirectories: true)
                    try Data("encoder".utf8).write(
                        to: encoderDirectoryURL.appendingPathComponent("coremldata.bin", isDirectory: false)
                    )
                }
            )

            try await manager.installDefaultEncoder()

            #expect(try manager.defaultModelReady())
            #expect(try manager.defaultEncoderReady())
            #expect(await downloadQueue.requestedURLs == [LocalWhisperModelManager.defaultEncoderArchiveDownloadURL])
        }

        @Test func installDefaultAssetsDownloadsModelAndExtractsEncoder() async throws {
            let modelsDirectoryURL = TestSupport.temporaryDirectoryURL()
            try FileManager.default.createDirectory(at: modelsDirectoryURL, withIntermediateDirectories: true)

            let downloadedModelURL = modelsDirectoryURL.appendingPathComponent("downloaded-model.bin")
            try Data("model".utf8).write(to: downloadedModelURL)

            let downloadedArchiveURL = modelsDirectoryURL.appendingPathComponent("downloaded-encoder.zip")
            try Data("archive".utf8).write(to: downloadedArchiveURL)

            let downloadQueue = DownloadQueue(urls: [downloadedModelURL, downloadedArchiveURL])
            let manager = LocalWhisperModelManager(
                modelsDirectoryProvider: { modelsDirectoryURL },
                runtimeAvailableProvider: { true },
                customPathProvider: { nil },
                downloadProvider: { url in
                    try await downloadQueue.next(requestedURL: url)
                },
                archiveExtractor: { _, destinationDirectoryURL in
                    let encoderDirectoryURL = destinationDirectoryURL.appendingPathComponent(
                        LocalWhisperModelManager.defaultEncoderDirectoryName,
                        isDirectory: true
                    )
                    try FileManager.default.createDirectory(at: encoderDirectoryURL, withIntermediateDirectories: true)
                    try Data("encoder".utf8).write(
                        to: encoderDirectoryURL.appendingPathComponent("coremldata.bin", isDirectory: false)
                    )
                }
            )

            try await manager.installDefaultAssets()

            #expect(FileManager.default.fileExists(atPath: try manager.defaultModelURL().path))
            #expect(try manager.defaultAssetsReady())
            #expect(await downloadQueue.requestedURLs.count == 2)
        }

        @Test func installDefaultAssetsSkipsDownloadWhenAssetsAlreadyExist() async throws {
            let modelsDirectoryURL = TestSupport.temporaryDirectoryURL()
            let encoderDirectoryURL = modelsDirectoryURL.appendingPathComponent(
                LocalWhisperModelManager.defaultEncoderDirectoryName,
                isDirectory: true
            )
            try FileManager.default.createDirectory(at: encoderDirectoryURL, withIntermediateDirectories: true)

            let modelURL = modelsDirectoryURL.appendingPathComponent(LocalWhisperModelDescriptor.default.fileName)
            try Data("model".utf8).write(to: modelURL)
            try Data("encoder".utf8).write(
                to: encoderDirectoryURL.appendingPathComponent("coremldata.bin", isDirectory: false)
            )

            let downloadQueue = DownloadQueue(urls: [])
            let manager = LocalWhisperModelManager(
                modelsDirectoryProvider: { modelsDirectoryURL },
                runtimeAvailableProvider: { true },
                customPathProvider: { nil },
                downloadProvider: { url in
                    try await downloadQueue.next(requestedURL: url)
                },
                archiveExtractor: { _, _ in
                    Issue.record("archiveExtractor should not run when assets already exist")
                }
            )

            try await manager.installDefaultAssets()

            #expect(await downloadQueue.requestedURLs.isEmpty)
            #expect(try manager.defaultAssetsReady())
        }
    }

    actor DownloadQueue {
        private var urls: [URL]
        private(set) var requestedURLs: [URL] = []

        init(urls: [URL]) {
            self.urls = urls
        }

        func next(requestedURL: URL) throws -> URL {
            requestedURLs.append(requestedURL)
            guard !urls.isEmpty else {
                throw TestError.expected
            }
            return urls.removeFirst()
        }
    }
#endif
