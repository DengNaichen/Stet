import Foundation

/// The complete set of files required by the shared SenseVoice runtime.
public enum SenseVoiceModelAsset: CaseIterable, Sendable {
    case model
    case tokens
    case vad

    public nonisolated var key: String {
        switch self {
        case .model: return "model"
        case .tokens: return "tokens"
        case .vad: return "vad"
        }
    }

    public nonisolated var fileName: String {
        switch self {
        case .model: return "model.int8.onnx"
        case .tokens: return "tokens.txt"
        case .vad: return "silero_vad.onnx"
        }
    }

    public nonisolated var downloadURL: URL {
        switch self {
        case .model:
            return URL(
                string: "https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/main/model.int8.onnx"
            )!
        case .tokens:
            return URL(
                string: "https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/main/tokens.txt"
            )!
        case .vad:
            return URL(
                string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx"
            )!
        }
    }
}

public enum SenseVoiceModelManagerError: LocalizedError, Sendable {
    case unsupportedModel(String)
    case modelsDirectoryUnavailable
    case modelNotDownloaded(asset: SenseVoiceModelAsset)
    case invalidDownloadResponse(URL, statusCode: Int?)
    case emptyDownloadedFile(URL)

    public nonisolated var errorDescription: String? {
        switch self {
        case .unsupportedModel(let name):
            return "Unsupported ASR model: \(name)."
        case .modelsDirectoryUnavailable:
            return "Stet could not resolve the local ASR models directory."
        case .modelNotDownloaded(let asset):
            return "SenseVoice asset is not downloaded: \(asset.fileName)."
        case .invalidDownloadResponse(let url, let statusCode):
            if let statusCode {
                return "SenseVoice download failed with HTTP \(statusCode): \(url.absoluteString)"
            }
            return "SenseVoice download returned an invalid response: \(url.absoluteString)"
        case .emptyDownloadedFile(let url):
            return "SenseVoice download produced an empty file: \(url.lastPathComponent)."
        }
    }
}

/// Cross-platform, on-demand storage for the one supported local ASR model.
///
/// Each app keeps its own copy in its Application Support sandbox, while the
/// asset version and source URLs stay identical on macOS and iOS.
public actor SenseVoiceModelManager: ASRModelManager {
    public nonisolated static let modelName = "SenseVoice"

    private let modelsDirectory: URL
    private let session: URLSession
    private var state: ASRModelStatus = .notDownloaded
    private var inFlightDownload: Task<Void, Error>?

    public init(
        modelsDirectory: URL? = nil,
        session: URLSession = .shared
    ) throws {
        self.modelsDirectory = try modelsDirectory ?? Self.defaultModelsDirectory()
        self.session = session
    }

    public nonisolated static func defaultModelsDirectory() throws -> URL {
        guard let applicationSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw SenseVoiceModelManagerError.modelsDirectoryUnavailable
        }

        return applicationSupportURL
            .appendingPathComponent("Stet", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent("SenseVoice", isDirectory: true)
    }

    public func status(for modelName: String) async -> ASRModelStatus {
        guard modelName == Self.modelName else {
            return .error(message: SenseVoiceModelManagerError.unsupportedModel(modelName).localizedDescription)
        }

        if let urls = try? readyURLs() {
            return .ready(localURL: urls[SenseVoiceModelAsset.model.key]!)
        }

        return state
    }

    public func resolveModelURLs(for modelName: String) async throws -> [String: URL] {
        try validate(modelName: modelName)
        return try readyURLs()
    }

    public func downloadIfNeeded(for modelName: String) async throws {
        try validate(modelName: modelName)

        if let urls = try? readyURLs() {
            state = .ready(localURL: urls[SenseVoiceModelAsset.model.key]!)
            return
        }

        if let inFlightDownload {
            return try await inFlightDownload.value
        }

        state = .downloading(progress: 0)
        let directory = modelsDirectory
        let session = session
        let task = Task {
            try await Self.downloadMissingAssets(into: directory, session: session)
        }
        inFlightDownload = task

        do {
            try await task.value
            let urls = try readyURLs()
            state = .ready(localURL: urls[SenseVoiceModelAsset.model.key]!)
            inFlightDownload = nil
        } catch {
            state = .error(message: error.localizedDescription)
            inFlightDownload = nil
            throw error
        }
    }

    private func validate(modelName: String) throws {
        guard modelName == Self.modelName else {
            throw SenseVoiceModelManagerError.unsupportedModel(modelName)
        }
    }

    private func readyURLs() throws -> [String: URL] {
        var urls: [String: URL] = [:]
        let fileManager = FileManager.default

        for asset in SenseVoiceModelAsset.allCases {
            let url = modelsDirectory.appendingPathComponent(asset.fileName, isDirectory: false)
            guard fileManager.fileExists(atPath: url.path) else {
                throw SenseVoiceModelManagerError.modelNotDownloaded(asset: asset)
            }
            urls[asset.key] = url
        }

        return urls
    }

    private nonisolated static func downloadMissingAssets(
        into directory: URL,
        session: URLSession
    ) async throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        for asset in SenseVoiceModelAsset.allCases {
            let destinationURL = directory.appendingPathComponent(asset.fileName, isDirectory: false)
            guard !fileManager.fileExists(atPath: destinationURL.path) else { continue }

            let (temporaryURL, response) = try await session.download(from: asset.downloadURL)
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            guard let statusCode, (200..<300).contains(statusCode) else {
                throw SenseVoiceModelManagerError.invalidDownloadResponse(asset.downloadURL, statusCode: statusCode)
            }

            let stagedURL = directory.appendingPathComponent(
                ".\(asset.fileName).\(UUID().uuidString).partial",
                isDirectory: false
            )
            try fileManager.moveItem(at: temporaryURL, to: stagedURL)

            do {
                let attributes = try fileManager.attributesOfItem(atPath: stagedURL.path)
                let size = attributes[.size] as? NSNumber
                guard (size?.intValue ?? 0) > 0 else {
                    throw SenseVoiceModelManagerError.emptyDownloadedFile(asset.downloadURL)
                }
                try fileManager.moveItem(at: stagedURL, to: destinationURL)
            } catch {
                try? fileManager.removeItem(at: stagedURL)
                throw error
            }
        }
    }
}
