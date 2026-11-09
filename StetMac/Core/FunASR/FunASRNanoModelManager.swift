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
        case encoder
        case languageModel
        case voiceActivityDetector

        nonisolated var fileName: String {
            switch self {
            case .encoder: return "funasr-encoder-f16.gguf"
            case .languageModel: return "qwen3-0.6b-q4km.gguf"
            case .voiceActivityDetector: return "fsmn-vad.gguf"
            }
        }

        nonisolated var downloadURL: URL {
            let urlString =
                switch self {
                case .encoder:
                    "https://huggingface.co/FunAudioLLM/Fun-ASR-Nano-GGUF/resolve/main/funasr-encoder-f16.gguf"
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
        private let downloader: ModelFileDownloader

        nonisolated init(
            modelsDirectoryProvider: (@Sendable () throws -> URL)? = nil,
            downloadProvider: DownloadProvider? = nil,
            downloader: ModelFileDownloader = .shared
        ) {
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
                encoder: directory.appendingPathComponent(FunASRNanoModelAsset.encoder.fileName),
                languageModel: directory.appendingPathComponent(FunASRNanoModelAsset.languageModel.fileName),
                voiceActivityDetector: directory.appendingPathComponent(
                    FunASRNanoModelAsset.voiceActivityDetector.fileName)
            )
        }

        nonisolated func isModelDownloaded() -> Bool {
            guard let files = try? modelFiles() else { return false }
            return zip(FunASRNanoModelAsset.allCases, files.allFiles).allSatisfy { asset, url in
                downloader.isAvailable(ModelFileRequest(official: asset.downloadURL), at: url)
            }
        }

        nonisolated func resolvedModelFiles() throws -> FunASRNanoModelFiles {
            let files = try modelFiles()
            let missing = zip(FunASRNanoModelAsset.allCases, files.allFiles).compactMap { asset, url in
                downloader.isAvailable(ModelFileRequest(official: asset.downloadURL), at: url) ? nil : url
            }
            guard missing.isEmpty else {
                throw FunASRNanoModelError.missingAssets(missing)
            }
            #if arch(arm64)
                if #available(macOS 15, *) {
                    let coreML = files.encoder.deletingLastPathComponent()
                        .appendingPathComponent("FunASRNanoANE-v1.mlmodelc", isDirectory: true)
                    var isDirectory: ObjCBool = false
                    if FileManager.default.fileExists(atPath: coreML.path, isDirectory: &isDirectory),
                        isDirectory.boolValue
                    {
                        return FunASRNanoModelFiles(
                            encoder: coreML,
                            languageModel: files.languageModel,
                            voiceActivityDetector: files.voiceActivityDetector
                        )
                    }
                }
            #endif
            return files
        }

        nonisolated func modelsDirectoryURL() throws -> URL {
            let directory = try modelsDirectoryProvider()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        }

        func installDefaultModel() async throws {
            let directory = try modelsDirectoryProvider()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            for asset in FunASRNanoModelAsset.allCases {
                let destination = directory.appendingPathComponent(asset.fileName)
                _ = try await downloader.file(ModelFileRequest(official: asset.downloadURL), at: destination)
            }
        }
    }
#endif
