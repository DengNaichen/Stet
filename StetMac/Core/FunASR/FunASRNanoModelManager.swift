#if os(macOS)
    import Foundation
    import StetASR
    import StetCore

    enum FunASRNanoModelError: LocalizedError, Equatable, Sendable {
        case modelDirectoryUnavailable
        case missingAssets([URL])
        case invalidDownloadResponse(URL, statusCode: Int?)

        nonisolated var errorDescription: String? {
            switch self {
            case .modelDirectoryUnavailable:
                return "Stet could not resolve the Fun-ASR models directory."
            case .missingAssets(let urls):
                return "Fun-ASR model components are missing: \(urls.map(\.lastPathComponent).joined(separator: ", "))."
            case .invalidDownloadResponse(let url, let statusCode):
                if let statusCode {
                    return "Fun-ASR asset download failed with status \(statusCode) for \(url.absoluteString)."
                }
                return "Fun-ASR asset download returned an invalid response for \(url.absoluteString)."
            }
        }
    }

    enum FunASRNanoModelAsset: CaseIterable, Sendable {
        case languageModel
        case voiceActivityDetector

        nonisolated var fileName: String {
            switch self {
            case .languageModel: return "qwen3-0.6b-q4km.gguf"
            case .voiceActivityDetector: return "fsmn-vad.gguf"
            }
        }

        nonisolated var downloadURL: URL {
            let urlString =
                switch self {
                case .languageModel:
                    "https://huggingface.co/FunAudioLLM/Fun-ASR-Nano-GGUF/resolve/main/qwen3-0.6b-q4km.gguf"
                case .voiceActivityDetector:
                    "https://huggingface.co/FunAudioLLM/fsmn-vad-GGUF/resolve/main/fsmn-vad.gguf"
                }
            return URL(string: urlString)!
        }
    }

    struct FunASRNanoModelManager: Sendable {
        typealias DownloadProvider = @Sendable (URL) async throws -> (URL, URLResponse)

        private let modelsDirectoryProvider: @Sendable () throws -> URL
        private let prepareEncoder: @Sendable (URL) async throws -> Void
        private let downloader: ModelFileDownloader

        nonisolated init(
            modelsDirectoryProvider: (@Sendable () throws -> URL)? = nil,
            downloadProvider: DownloadProvider? = nil,
            downloader: ModelFileDownloader = .shared,
            prepareEncoder: (@Sendable (URL) async throws -> Void)? = nil
        ) {
            self.prepareEncoder =
                prepareEncoder ?? { directory in
                    let installer =
                        modelsDirectoryProvider == nil
                        ? FunASRNanoANEInstaller.shared
                        : FunASRNanoANEInstaller(
                            directoryProvider: { directory }, release: FunASRNanoANECatalog.bundled())
                    if ANEModelReadiness.installed(in: directory) != nil {
                        try await installer.prepareInstalled { _ in }
                    } else {
                        try await installer.download { _ in }
                    }
                }
            self.modelsDirectoryProvider =
                modelsDirectoryProvider ?? {
                    guard
                        let applicationSupportURL = FileManager.default.urls(
                            for: .applicationSupportDirectory,
                            in: .userDomainMask
                        ).first
                    else {
                        throw FunASRNanoModelError.modelDirectoryUnavailable
                    }
                    return
                        applicationSupportURL
                        .appendingPathComponent("Stet", isDirectory: true)
                        .appendingPathComponent("Models", isDirectory: true)
                        .appendingPathComponent("Fun-ASR-Nano", isDirectory: true)
                }
            if let downloadProvider {
                self.downloader = ModelFileDownloader { url, destination, _ in
                    let (temporary, response) = try await downloadProvider(url)
                    defer { try? FileManager.default.removeItem(at: temporary) }
                    guard let response = response as? HTTPURLResponse,
                        (200...299).contains(response.statusCode)
                    else {
                        throw FunASRNanoModelError.invalidDownloadResponse(
                            url, statusCode: (response as? HTTPURLResponse)?.statusCode)
                    }
                    try FileManager.default.moveItem(at: temporary, to: destination)
                }
            } else {
                self.downloader = downloader
            }
        }

        nonisolated func modelFiles() throws -> FunASRNanoModelFiles {
            let directory = try modelsDirectoryProvider()
            return FunASRNanoModelFiles(
                encoder: ANEModelReadiness.installed(in: directory)?.compiledURL(in: directory)
                    ?? directory.appendingPathComponent(FunASRNanoANEManifest.compiledName, isDirectory: true),
                languageModel: directory.appendingPathComponent(FunASRNanoModelAsset.languageModel.fileName),
                voiceActivityDetector: directory.appendingPathComponent(
                    FunASRNanoModelAsset.voiceActivityDetector.fileName)
            )
        }

        nonisolated func isModelDownloaded() -> Bool {
            (try? resolvedModelFiles()) != nil
        }

        nonisolated func missingCompanionFiles(in directory: URL) -> [URL] {
            FunASRNanoModelAsset.allCases.compactMap { asset in
                let url = directory.appendingPathComponent(asset.fileName)
                return downloader.isAvailable(ModelFileRequest(official: asset.downloadURL), at: url) ? nil : url
            }
        }

        nonisolated func resolvedModelFiles() throws -> FunASRNanoModelFiles {
            let directory = try modelsDirectoryProvider()
            let missing = missingCompanionFiles(in: directory)
            guard missing.isEmpty else { throw FunASRNanoModelError.missingAssets(missing) }
            guard ANEModelReadiness.read(in: directory) != nil else { throw ANEModelInstallError.encoderNotReady }
            return try modelFiles()
        }

        nonisolated func modelsDirectoryURL() throws -> URL {
            let directory = try modelsDirectoryProvider()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        }

        func installDefaultModel() async throws {
            let directory = try modelsDirectoryProvider()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            guard ANEModelReadiness.supported else { throw ANEModelInstallError.unsupported }
            for asset in FunASRNanoModelAsset.allCases {
                let destination = directory.appendingPathComponent(asset.fileName)
                _ = try await downloader.file(ModelFileRequest(official: asset.downloadURL), at: destination)
            }
            if ANEModelReadiness.read(in: directory) == nil { try await prepareEncoder(directory) }
        }
    }
#endif
