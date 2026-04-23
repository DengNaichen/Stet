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
                downloadProvider: { url, _ in
                    try await downloadQueue.next(requestedURL: url)
                }
            )

            try await manager.installDefaultModel()

            #expect(try manager.defaultModelReady())
            #expect(!(try manager.defaultEncoderReady()))
            #expect(await downloadQueue.requestedURLs == [LocalWhisperModelManager.defaultModelDownloadURL])
        }

        @Test func installDefaultAssetsDownloadsOnlyModel() async throws {
            let modelsDirectoryURL = TestSupport.temporaryDirectoryURL()
            try FileManager.default.createDirectory(at: modelsDirectoryURL, withIntermediateDirectories: true)

            let downloadedModelURL = modelsDirectoryURL.appendingPathComponent("downloaded-model.bin")
            try Data("model".utf8).write(to: downloadedModelURL)

            let downloadQueue = DownloadQueue(urls: [downloadedModelURL])
            let manager = LocalWhisperModelManager(
                modelsDirectoryProvider: { modelsDirectoryURL },
                runtimeAvailableProvider: { true },
                customPathProvider: { nil },
                downloadProvider: { url, _ in
                    try await downloadQueue.next(requestedURL: url)
                }
            )

            try await manager.installDefaultAssets(progress: { _ in }, downloadProgress: { _, _, _ in })

            #expect(try manager.defaultModelReady())
            #expect(!(try manager.defaultEncoderReady()))
            #expect(try manager.defaultAssetsReady())
            #expect(await downloadQueue.requestedURLs == [LocalWhisperModelManager.defaultModelDownloadURL])
        }

        @Test func installDefaultAssetsRemovesExistingEncoder() async throws {
            let modelsDirectoryURL = TestSupport.temporaryDirectoryURL()
            let encoderDirectoryURL = modelsDirectoryURL.appendingPathComponent(
                LocalWhisperModelManager.defaultEncoderDirectoryName,
                isDirectory: true
            )
            try FileManager.default.createDirectory(at: encoderDirectoryURL, withIntermediateDirectories: true)

            let downloadedModelURL = modelsDirectoryURL.appendingPathComponent("downloaded-model.bin")
            try Data("model".utf8).write(to: downloadedModelURL)
            try Data("encoder".utf8).write(
                to: encoderDirectoryURL.appendingPathComponent("coremldata.bin", isDirectory: false)
            )

            let downloadQueue = DownloadQueue(urls: [downloadedModelURL])
            let manager = LocalWhisperModelManager(
                modelsDirectoryProvider: { modelsDirectoryURL },
                runtimeAvailableProvider: { true },
                customPathProvider: { nil },
                downloadProvider: { url, _ in
                    try await downloadQueue.next(requestedURL: url)
                }
            )

            try await manager.installDefaultAssets(progress: { _ in }, downloadProgress: { _, _, _ in })

            #expect(FileManager.default.fileExists(atPath: try manager.defaultModelURL().path))
            #expect(!(try manager.defaultEncoderReady()))
            #expect(try manager.defaultAssetsReady())
            #expect(await downloadQueue.requestedURLs == [LocalWhisperModelManager.defaultModelDownloadURL])
        }

        @Test func installDefaultAssetsSkipsDownloadWhenModelExistsAndRemovesExistingEncoder() async throws {
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
                downloadProvider: { url, _ in
                    try await downloadQueue.next(requestedURL: url)
                }
            )

            try await manager.installDefaultAssets(progress: { _ in }, downloadProgress: { _, _, _ in })

            #expect(await downloadQueue.requestedURLs.isEmpty)
            #expect(!(try manager.defaultEncoderReady()))
            #expect(try manager.defaultAssetsReady())
        }

        @Test func resolvingDefaultModelRemovesExistingEncoder() throws {
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

            let manager = LocalWhisperModelManager(
                modelsDirectoryProvider: { modelsDirectoryURL },
                runtimeAvailableProvider: { true },
                customPathProvider: { nil }
            )

            let resolvedURL = try manager.resolvedModelURL()

            #expect(resolvedURL == modelURL)
            #expect(!(try manager.defaultEncoderReady()))
        }

        @Test func installDefaultModelForwardsDownloadProgress() async throws {
            let modelsDirectoryURL = TestSupport.temporaryDirectoryURL()
            try FileManager.default.createDirectory(at: modelsDirectoryURL, withIntermediateDirectories: true)

            let downloadedModelURL = modelsDirectoryURL.appendingPathComponent("downloaded-model.bin")
            try Data("model".utf8).write(to: downloadedModelURL)

            let downloadQueue = DownloadQueue(urls: [downloadedModelURL])
            let manager = LocalWhisperModelManager(
                modelsDirectoryProvider: { modelsDirectoryURL },
                runtimeAvailableProvider: { true },
                customPathProvider: { nil },
                downloadProvider: { url, progressSink in
                    progressSink.update(fraction: 0.15, completed: 15, total: 100)
                    progressSink.update(fraction: 0.72, completed: 72, total: 100)
                    return try await downloadQueue.next(requestedURL: url)
                }
            )

            var reportedProgress: [Double] = []
            try await manager.installDefaultModel(downloadProgress: { fraction, _, _ in
                reportedProgress.append(fraction)
            })

            #expect(try manager.defaultModelReady())
            #expect(reportedProgress.contains(0.15))
            #expect(reportedProgress.contains(0.72))
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
