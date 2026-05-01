import Foundation

struct LocalWhisperModelDescriptor: Sendable, Equatable {
    let displayName: String
    let fileName: String

    nonisolated static let `default` = LocalWhisperModelDescriptor(
        displayName: "Whisper large v3 turbo q5_0",
        fileName: "ggml-large-v3-turbo-q5_0.bin"
    )

    /// Returns a descriptor inferred from an arbitrary file URL.
    nonisolated static func from(url: URL) -> LocalWhisperModelDescriptor {
        LocalWhisperModelDescriptor(
            displayName: url.lastPathComponent,
            fileName: url.lastPathComponent
        )
    }
}

enum LocalWhisperDownloadStage: String, Sendable {
    case checkingExistingAssets
    case downloadingModel
    case ready
}

enum LocalWhisperModelStatus: Sendable, Equatable {
    case ready(localURL: URL)
    case missing(expectedURL: URL)
    case runtimeUnavailable(expectedURL: URL)
}

enum LocalWhisperError: LocalizedError, Equatable, Sendable {
    case modelDirectoryUnavailable
    case modelMissing(expectedURL: URL)
    case runtimeUnavailable
    case audioPreparationFailed
    case transcriptionFailed
    case downloadFailed(URL)
    case invalidDownloadResponse(URL, statusCode: Int?)

    nonisolated var errorDescription: String? {
        switch self {
        case .modelDirectoryUnavailable:
            #if os(macOS)
                return
                    "Stet could not resolve the Local Whisper models directory. Please check your system permissions."
            #else
                return "Internal storage error. Please reinstall the application."
            #endif
        case .modelMissing(let expectedURL):
            #if os(macOS)
                return "Local Whisper model not found. Place the model at \(expectedURL.path) or check Settings."
            #else
                return "Local Whisper model components are missing. Please reinstall the application."
            #endif
        case .runtimeUnavailable:
            #if os(macOS)
                return "Local Whisper runtime is not linked in this build. This might be a configuration issue."
            #else
                return "This device is not compatible with Local Whisper transcription."
            #endif
        case .audioPreparationFailed:
            return "Stet could not prepare audio for Local Whisper transcription. Ensure microphone access is granted."
        case .transcriptionFailed:
            return "Local Whisper transcription failed. Please try again."
        case .downloadFailed(let url):
            return
                "Stet could not download Local Whisper assets from \(url.absoluteString). Please check your internet connection."
        case .invalidDownloadResponse(let url, let statusCode):
            if let statusCode {
                return "Local Whisper asset download failed with status \(statusCode) for \(url.absoluteString)."
            }
            return "Local Whisper asset download returned an invalid response for \(url.absoluteString)."
        }
    }
}

struct LocalWhisperModelManager: Sendable {
    nonisolated static let defaultModelDownloadURL = URL(
        string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin"
    )!
    nonisolated static let defaultEncoderDirectoryName = "ggml-large-v3-turbo-encoder.mlmodelc"

    private let model: LocalWhisperModelDescriptor
    private let configuration: any ModelStorageConfiguration
    private let modelsDirectoryProvider: @Sendable () throws -> URL
    private let runtimeAvailableProvider: @Sendable () -> Bool
    private let downloadProvider: @Sendable (URL, LocalWhisperDownloadProgressSink) async throws -> URL

    nonisolated init(
        model: LocalWhisperModelDescriptor = .default,
        configuration: any ModelStorageConfiguration = UserDefaultsModelStorage(),
        modelsDirectoryProvider: (@Sendable () throws -> URL)? = nil,
        runtimeAvailableProvider: (@Sendable () -> Bool)? = nil,
        downloadProvider: (@Sendable (URL, LocalWhisperDownloadProgressSink) async throws -> URL)? = nil
    ) {
        self.model = model
        self.configuration = configuration
        self.modelsDirectoryProvider =
            modelsDirectoryProvider
            ?? {
                guard
                    let applicationSupportURL = FileManager.default.urls(
                        for: .applicationSupportDirectory,
                        in: .userDomainMask
                    ).first
                else {
                    throw LocalWhisperError.modelDirectoryUnavailable
                }

                return
                    applicationSupportURL
                    .appendingPathComponent("Stet", isDirectory: true)
                    .appendingPathComponent("Models", isDirectory: true)
            }
        self.runtimeAvailableProvider = runtimeAvailableProvider ?? { LocalWhisperEngineFactory.isRuntimeAvailable }
        self.downloadProvider = downloadProvider ?? Self.defaultDownloadProvider
    }

    /// Saves a custom model path to UserDefaults.
    nonisolated func saveCustomModelPath(_ path: String?) {
        Self.scheduleContextCleanup()
        configuration.saveLocalWhisperModelPath(path)
    }

    nonisolated private static func scheduleContextCleanup() {
        #if os(macOS)
            Task { @MainActor in
                await LocalWhisperContextManager.shared.cleanupResources()
            }
        #endif
    }

    /// Returns the custom path URL when it is set and the file exists.
    nonisolated private func resolvedCustomURL() -> URL? {
        guard let path = configuration.localWhisperModelPath, !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    nonisolated var modelDescriptor: LocalWhisperModelDescriptor {
        if let customURL = resolvedCustomURL() {
            return .from(url: customURL)
        }
        return model
    }

    nonisolated func status() throws -> LocalWhisperModelStatus {
        // Custom path takes priority over the default Stet models directory.
        if let customURL = resolvedCustomURL() {
            guard runtimeAvailableProvider() else {
                return .runtimeUnavailable(expectedURL: customURL)
            }
            return .ready(localURL: customURL)
        }

        let expectedURL = try expectedModelURL()

        guard runtimeAvailableProvider() else {
            return .runtimeUnavailable(expectedURL: expectedURL)
        }

        if FileManager.default.fileExists(atPath: expectedURL.path) {
            return .ready(localURL: expectedURL)
        }

        return .missing(expectedURL: expectedURL)
    }

    nonisolated func resolvedModelURL() throws -> URL {
        switch try status() {
        case .ready(let localURL):
            try removeDefaultEncoderIfNeeded(for: localURL)
            return localURL
        case .missing(let expectedURL):
            throw LocalWhisperError.modelMissing(expectedURL: expectedURL)
        case .runtimeUnavailable:
            throw LocalWhisperError.runtimeUnavailable
        }
    }

    nonisolated func expectedModelURL() throws -> URL {
        if let customURL = resolvedCustomURL() {
            return customURL
        }
        return try defaultModelURL()
    }

    nonisolated func defaultModelURL() throws -> URL {
        let modelsDirectoryURL = try ensureModelsDirectoryExists()
        return modelsDirectoryURL.appendingPathComponent(model.fileName, isDirectory: false)
    }

    nonisolated func defaultEncoderDirectoryURL() throws -> URL {
        let modelsDirectoryURL = try ensureModelsDirectoryExists()
        return modelsDirectoryURL.appendingPathComponent(Self.defaultEncoderDirectoryName, isDirectory: true)
    }

    nonisolated func defaultModelReady() throws -> Bool {
        let modelURL = try defaultModelURL()
        return FileManager.default.fileExists(atPath: modelURL.path)
    }

    nonisolated func defaultEncoderReady() throws -> Bool {
        let encoderDirectoryURL = try defaultEncoderDirectoryURL()

        var isDirectory: ObjCBool = false
        let encoderExists = FileManager.default.fileExists(atPath: encoderDirectoryURL.path, isDirectory: &isDirectory)

        return encoderExists && isDirectory.boolValue
    }

    nonisolated func defaultAssetsReady() throws -> Bool {
        try defaultModelReady() && !defaultEncoderReady()
    }

    nonisolated func installDefaultModel(
        progress: @Sendable (LocalWhisperDownloadStage) -> Void = { _ in },
        downloadProgress: @escaping @Sendable (Double, Int64, Int64) -> Void = { _, _, _ in }
    ) async throws {
        progress(.checkingExistingAssets)

        if try defaultModelReady() {
            try removeDefaultEncoderIfPresent()
            downloadProgress(1.0, 0, 0)
            progress(.ready)
            return
        }

        progress(.downloadingModel)
        let progressSink = LocalWhisperDownloadProgressSink(handler: downloadProgress)
        let downloadedModelURL = try await downloadProvider(Self.defaultModelDownloadURL, progressSink)
        let destinationURL = try defaultModelURL()
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.moveItem(at: downloadedModelURL, to: destinationURL)
        try removeDefaultEncoderIfPresent()

        progress(.ready)
    }

    nonisolated func installDefaultAssets(
        progress: @Sendable (LocalWhisperDownloadStage) -> Void = { _ in },
        downloadProgress: @escaping @Sendable (Double, Int64, Int64) -> Void = { _, _, _ in }
    ) async throws {
        if try !defaultModelReady() {
            try await installDefaultModel(progress: progress, downloadProgress: downloadProgress)
        }

        try removeDefaultEncoderIfPresent()

        progress(.ready)
    }

    nonisolated func removeDefaultEncoderIfPresent() throws {
        let encoderDirectoryURL = try defaultEncoderDirectoryURL()
        guard FileManager.default.fileExists(atPath: encoderDirectoryURL.path) else { return }
        try FileManager.default.removeItem(at: encoderDirectoryURL)
        Self.scheduleContextCleanup()
    }

    private nonisolated func removeDefaultEncoderIfNeeded(for modelURL: URL) throws {
        let defaultModelURL = try defaultModelURL()
        guard modelURL.standardizedFileURL.path == defaultModelURL.standardizedFileURL.path else { return }
        try removeDefaultEncoderIfPresent()
    }

    nonisolated func statusMessage() -> String {
        let expectedPath: String

        do {
            expectedPath = try expectedModelURL().path
        } catch {
            return LocalWhisperError.modelDirectoryUnavailable.localizedDescription
        }

        do {
            switch try status() {
            case .ready:
                return "Local Whisper model is available at \(expectedPath)."
            case .missing:
                return "Place \(model.fileName) at \(expectedPath)."
            case .runtimeUnavailable:
                return "Local Whisper runtime is not linked in this build. Expected model path: \(expectedPath)."
            }
        } catch {
            return error.localizedDescription
        }
    }

    nonisolated func needsAttention() -> Bool {
        do {
            switch try status() {
            case .ready:
                return false
            case .missing, .runtimeUnavailable:
                return true
            }
        } catch {
            return true
        }
    }

    @discardableResult
    nonisolated func ensureModelsDirectoryExists() throws -> URL {
        let url = try modelsDirectory()
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    nonisolated private func modelsDirectory() throws -> URL {
        try modelsDirectoryProvider()
    }

    nonisolated private static func downloadFile(
        from url: URL,
        progressSink: LocalWhisperDownloadProgressSink
    ) async throws -> URL {
        let downloader = ProgressReportingDownloadCoordinator(
            requestURL: url,
            progressSink: progressSink
        )
        return try await downloader.download()
    }

    nonisolated private static func defaultDownloadProvider(
        _ url: URL,
        progressSink: LocalWhisperDownloadProgressSink
    ) async throws -> URL {
        try await downloadFile(from: url, progressSink: progressSink)
    }
}

final class LocalWhisperDownloadProgressSink: @unchecked Sendable {
    private let handler: @Sendable (Double, Int64, Int64) -> Void

    init(handler: @escaping @Sendable (Double, Int64, Int64) -> Void) {
        self.handler = handler
    }

    func update(fraction: Double, completed: Int64, total: Int64) {
        handler(fraction, completed, total)
    }
}

private final class ProgressReportingDownloadCoordinator: NSObject, URLSessionDownloadDelegate {
    private let requestURL: URL
    private let progressSink: LocalWhisperDownloadProgressSink
    private let stagedDownloadURL: URL
    private var continuation: CheckedContinuation<URL, Error>?
    private var session: URLSession?

    init(requestURL: URL, progressSink: LocalWhisperDownloadProgressSink) {
        self.requestURL = requestURL
        self.progressSink = progressSink
        self.stagedDownloadURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "Stet-LocalWhisper-\(UUID().uuidString)-\(requestURL.lastPathComponent)", isDirectory: false)
    }

    func download() async throws -> URL {
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            let configuration = URLSessionConfiguration.default
            let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
            self.session = session

            let task = session.downloadTask(with: requestURL)
            task.resume()
        }
    }

    // MARK: - URLSessionDownloadDelegate

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let fraction =
            totalBytesExpectedToWrite > 0
            ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            : 0
        progressSink.update(
            fraction: max(0, min(1, fraction)),
            completed: totalBytesWritten,
            total: totalBytesExpectedToWrite
        )
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        do {
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: stagedDownloadURL.path) {
                try fileManager.removeItem(at: stagedDownloadURL)
            }
            try fileManager.moveItem(at: location, to: stagedDownloadURL)
            progressSink.update(fraction: 1.0, completed: 0, total: 0)
            resumeIfNeeded(returning: stagedDownloadURL)
        } catch {
            resumeIfNeeded(with: error)
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error {
            resumeIfNeeded(with: error)
        } else {
            // Success is handled in didFinishDownloadingTo
        }
    }

    private func resumeIfNeeded(returning url: URL) {
        guard let continuation else { return }
        self.continuation = nil
        self.session = nil
        continuation.resume(returning: url)
    }

    private func resumeIfNeeded(with error: Error) {
        guard let continuation else { return }
        self.continuation = nil
        self.session = nil
        continuation.resume(throwing: error)
    }
}
