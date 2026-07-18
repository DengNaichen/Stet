import Foundation

enum WhisperModelManagerError: LocalizedError, Sendable {
    case unsupportedModel(String)
    case modelsDirectoryUnavailable
    case modelNotDownloaded
    case invalidDownloadResponse(URL, statusCode: Int?)
    case emptyDownloadedFile(URL)

    nonisolated var errorDescription: String? {
        switch self {
        case .unsupportedModel(let name):
            return "Unsupported ASR model: \(name)."
        case .modelsDirectoryUnavailable:
            return "Stet could not resolve the local Whisper models directory."
        case .modelNotDownloaded:
            return "Whisper large-v3-turbo is not downloaded."
        case .invalidDownloadResponse(let url, let statusCode):
            if let statusCode {
                return "Whisper download failed with HTTP \(statusCode): \(url.absoluteString)"
            }
            return "Whisper download returned an invalid response: \(url.absoluteString)"
        case .emptyDownloadedFile(let url):
            return "Whisper download produced an empty file: \(url.lastPathComponent)."
        }
    }
}

actor WhisperModelManager: ASRModelManager {
    nonisolated static let modelName = "Whisper large-v3-turbo q5_0"
    nonisolated static let modelFileName = "ggml-large-v3-turbo-q5_0.bin"
    nonisolated static let modelKey = "model"
    nonisolated static let defaultDownloadURL = URL(
        string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin"
    )!

    private let modelsDirectory: URL
    private let session: URLSession
    private let downloadURL: URL
    private var state: ASRModelStatus = .notDownloaded
    private var inFlightDownload: Task<Void, Error>?

    init(
        modelsDirectory: URL? = nil,
        session: URLSession = .shared,
        downloadURL: URL = WhisperModelManager.defaultDownloadURL
    ) throws {
        self.modelsDirectory = try modelsDirectory ?? Self.defaultModelsDirectory()
        self.session = session
        self.downloadURL = downloadURL
    }

    nonisolated static func defaultModelsDirectory() throws -> URL {
        guard
            let applicationSupportURL = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first
        else {
            throw WhisperModelManagerError.modelsDirectoryUnavailable
        }

        return
            applicationSupportURL
            .appendingPathComponent("Stet", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent("Whisper", isDirectory: true)
    }

    func status(for modelName: String) async -> ASRModelStatus {
        guard modelName == Self.modelName else {
            return .error(message: WhisperModelManagerError.unsupportedModel(modelName).localizedDescription)
        }

        if let modelURL = try? readyModelURL() {
            return .ready(localURL: modelURL)
        }

        return state
    }

    func resolveModelURLs(for modelName: String) async throws -> [String: URL] {
        try validate(modelName: modelName)
        return [Self.modelKey: try readyModelURL()]
    }

    func downloadIfNeeded(for modelName: String) async throws {
        try validate(modelName: modelName)

        if let modelURL = try? readyModelURL() {
            state = .ready(localURL: modelURL)
            return
        }

        if let inFlightDownload {
            return try await inFlightDownload.value
        }

        state = .downloading(progress: 0)
        let directory = modelsDirectory
        let session = session
        let downloadURL = downloadURL
        let task = Task {
            try await Self.downloadModel(from: downloadURL, into: directory, session: session)
        }
        inFlightDownload = task

        do {
            try await task.value
            let modelURL = try readyModelURL()
            state = .ready(localURL: modelURL)
            inFlightDownload = nil
        } catch {
            state = .error(message: error.localizedDescription)
            inFlightDownload = nil
            throw error
        }
    }

    func deleteModel(for modelName: String) async throws {
        try validate(modelName: modelName)

        if let inFlightDownload {
            inFlightDownload.cancel()
            _ = try? await inFlightDownload.value
            self.inFlightDownload = nil
        }

        do {
            if FileManager.default.fileExists(atPath: modelsDirectory.path) {
                try FileManager.default.removeItem(at: modelsDirectory)
            }
            state = .notDownloaded
        } catch {
            state = .error(message: error.localizedDescription)
            throw error
        }
    }

    private func validate(modelName: String) throws {
        guard modelName == Self.modelName else {
            throw WhisperModelManagerError.unsupportedModel(modelName)
        }
    }

    private func readyModelURL() throws -> URL {
        let modelURL = modelsDirectory.appendingPathComponent(Self.modelFileName, isDirectory: false)
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            throw WhisperModelManagerError.modelNotDownloaded
        }
        return modelURL
    }

    private nonisolated static func downloadModel(
        from downloadURL: URL,
        into directory: URL,
        session: URLSession
    ) async throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let destinationURL = directory.appendingPathComponent(Self.modelFileName, isDirectory: false)
        guard !fileManager.fileExists(atPath: destinationURL.path) else { return }

        let (temporaryURL, response) = try await session.download(from: downloadURL)
        try Task.checkCancellation()

        let statusCode = (response as? HTTPURLResponse)?.statusCode
        guard let statusCode, (200..<300).contains(statusCode) else {
            throw WhisperModelManagerError.invalidDownloadResponse(downloadURL, statusCode: statusCode)
        }

        let stagedURL = directory.appendingPathComponent(
            ".\(Self.modelFileName).\(UUID().uuidString).partial",
            isDirectory: false
        )
        try fileManager.moveItem(at: temporaryURL, to: stagedURL)

        do {
            let attributes = try fileManager.attributesOfItem(atPath: stagedURL.path)
            let size = attributes[.size] as? NSNumber
            guard (size?.intValue ?? 0) > 0 else {
                throw WhisperModelManagerError.emptyDownloadedFile(downloadURL)
            }
            try fileManager.moveItem(at: stagedURL, to: destinationURL)
        } catch {
            try? fileManager.removeItem(at: stagedURL)
            throw error
        }
    }
}
