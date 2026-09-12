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

        static let coremlEncoderFileName = "FunASRNanoEncoder.mlmodelc"

        nonisolated static func compiledCoreMLEncoderURL(in directory: URL) -> URL? {
            let encoder = directory.appendingPathComponent(coremlEncoderFileName, isDirectory: true)
            let mil = encoder.appendingPathComponent("model.mil")
            guard FileManager.default.fileExists(atPath: mil.path) else { return nil }
            return encoder
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
        private let downloadProvider: DownloadProvider

        nonisolated init(
            modelsDirectoryProvider: (@Sendable () throws -> URL)? = nil,
            downloadProvider: DownloadProvider? = nil
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
            self.downloadProvider =
                downloadProvider ?? { url in
                    try await Self.downloadUsingMirrors(official: url)
                }
        }

        private static func downloadUsingMirrors(official: URL) async throws -> (URL, URLResponse) {
            var lastError: Error?
            for url in ModelDownloadMirror.candidates(for: official) {
                do {
                    let (file, response) = try await ModelDownloadMirror.urlSession.download(from: url)
                    if let httpResponse = response as? HTTPURLResponse,
                        (200...299).contains(httpResponse.statusCode)
                    {
                        return (file, response)
                    }
                    try? FileManager.default.removeItem(at: file)
                    lastError = FunASRNanoModelError.invalidDownloadResponse(
                        url,
                        statusCode: (response as? HTTPURLResponse)?.statusCode
                    )
                } catch {
                    lastError = error
                }
            }
            throw lastError ?? FunASRNanoModelError.invalidDownloadResponse(official, statusCode: nil)
        }

        nonisolated func modelFiles() throws -> FunASRNanoModelFiles {
            let directory = try modelsDirectoryProvider()
            let encoder =
                FunASRNanoModelAsset.compiledCoreMLEncoderURL(in: directory)
                ?? directory.appendingPathComponent(FunASRNanoModelAsset.encoder.fileName)
            return FunASRNanoModelFiles(
                encoder: encoder,
                languageModel: directory.appendingPathComponent(FunASRNanoModelAsset.languageModel.fileName),
                voiceActivityDetector: directory.appendingPathComponent(
                    FunASRNanoModelAsset.voiceActivityDetector.fileName)
            )
        }

        nonisolated func isModelDownloaded() -> Bool {
            guard let files = try? modelFiles() else { return false }
            return files.allFiles.allSatisfy { FileManager.default.fileExists(atPath: $0.path) }
        }

        nonisolated func resolvedModelFiles() throws -> FunASRNanoModelFiles {
            let files = try modelFiles()
            let missing = files.allFiles.filter { !FileManager.default.fileExists(atPath: $0.path) }
            guard missing.isEmpty else {
                throw FunASRNanoModelError.missingAssets(missing)
            }
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
                guard !FileManager.default.fileExists(atPath: destination.path) else { continue }

                let (downloadedFile, response) = try await downloadProvider(asset.downloadURL)
                guard let httpResponse = response as? HTTPURLResponse,
                    (200...299).contains(httpResponse.statusCode)
                else {
                    try? FileManager.default.removeItem(at: downloadedFile)
                    throw FunASRNanoModelError.invalidDownloadResponse(
                        asset.downloadURL,
                        statusCode: (response as? HTTPURLResponse)?.statusCode
                    )
                }

                do {
                    try FileManager.default.moveItem(at: downloadedFile, to: destination)
                } catch {
                    try? FileManager.default.removeItem(at: downloadedFile)
                    throw error
                }
            }
        }
    }
#endif
