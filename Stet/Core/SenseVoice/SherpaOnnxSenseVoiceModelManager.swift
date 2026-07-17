import Foundation
import StetCore

/// Model manager for Sherpa-ONNX based SenseVoice.
/// Manages ONNX model files instead of GGUF files.
struct SherpaOnnxSenseVoiceModelManager: Sendable {
    nonisolated static let defaultModelFileName = "model.int8.onnx"
    nonisolated static let defaultTokensFileName = "tokens.txt"
    nonisolated static let defaultModelDownloadURL = URL(
        string:
            "https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/main/model.int8.onnx"
    )!
    nonisolated static let defaultTokensDownloadURL = URL(
        string:
            "https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/main/tokens.txt"
    )!
    nonisolated static let displayName = "SenseVoice (Sherpa-ONNX, Chinese-optimized)"

    private let configuration: any ModelStorageConfiguration
    private let runtimeAvailableProvider: @Sendable () -> Bool
    private let modelsDirectoryProvider: @Sendable () throws -> URL
    private let downloadProvider: @Sendable (URL, LocalWhisperDownloadProgressSink) async throws -> URL

    nonisolated init(
        configuration: any ModelStorageConfiguration = UserDefaultsModelStorage(),
        runtimeAvailableProvider: (@Sendable () -> Bool)? = nil,
        modelsDirectoryProvider: (@Sendable () throws -> URL)? = nil,
        downloadProvider: (@Sendable (URL, LocalWhisperDownloadProgressSink) async throws -> URL)? = nil
    ) {
        self.configuration = configuration
        self.runtimeAvailableProvider =
            runtimeAvailableProvider ?? {
                #if canImport(sherpa_onnx)
                    return true
                #else
                    return false
                #endif
            }
        self.modelsDirectoryProvider =
            modelsDirectoryProvider
            ?? {
                guard
                    let applicationSupportURL = FileManager.default.urls(
                        for: .applicationSupportDirectory,
                        in: .userDomainMask
                    ).first
                else {
                    throw SenseVoiceError.modelDirectoryUnavailable
                }
                return
                    applicationSupportURL
                    .appendingPathComponent("Stet", isDirectory: true)
                    .appendingPathComponent("Models", isDirectory: true)
                    .appendingPathComponent("SherpaOnnxSenseVoice", isDirectory: true)
            }
        self.downloadProvider = downloadProvider ?? Self.defaultDownloadProvider
    }

    nonisolated func saveCustomModelPath(_ path: String?) {
        configuration.saveSherpaOnnxSenseVoiceModelPath(path)
    }

    nonisolated private func resolvedCustomURL() -> URL? {
        guard let path = configuration.sherpaOnnxSenseVoiceModelPath, !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    nonisolated func defaultModelURL() throws -> URL {
        let modelsDirectoryURL = try ensureModelsDirectoryExists()
        return modelsDirectoryURL.appendingPathComponent(Self.defaultModelFileName, isDirectory: false)
    }

    nonisolated func defaultTokensURL() throws -> URL {
        let modelsDirectoryURL = try ensureModelsDirectoryExists()
        return modelsDirectoryURL.appendingPathComponent(Self.defaultTokensFileName, isDirectory: false)
    }

    /// Locate the tokens.txt that pairs with the resolved model.
    /// We look in the same directory as the model file — both for the default
    /// download location and for user-picked custom paths.
    nonisolated func resolvedTokensURL() throws -> URL {
        let modelURL = try resolvedModelURL()
        let tokensURL = modelURL.deletingLastPathComponent()
            .appendingPathComponent(Self.defaultTokensFileName, isDirectory: false)
        guard FileManager.default.fileExists(atPath: tokensURL.path) else {
            throw SenseVoiceError.modelMissing(expectedURL: tokensURL)
        }
        return tokensURL
    }

    nonisolated func isModelDownloaded() -> Bool {
        // Custom path takes priority — but we still require tokens.txt next to it.
        if let modelURL = resolvedCustomURL() {
            let tokens = modelURL.deletingLastPathComponent()
                .appendingPathComponent(Self.defaultTokensFileName)
            return FileManager.default.fileExists(atPath: tokens.path)
        }
        // Default location: both files must exist.
        guard
            let modelURL = try? defaultModelURL(),
            let tokensURL = try? defaultTokensURL()
        else { return false }
        let fm = FileManager.default
        return fm.fileExists(atPath: modelURL.path) && fm.fileExists(atPath: tokensURL.path)
    }

    nonisolated func status() -> SenseVoiceModelStatus {
        guard runtimeAvailableProvider() else { return .runtimeUnavailable }

        if let modelURL = resolvedCustomURL() {
            let tokensURL = modelURL.deletingLastPathComponent()
                .appendingPathComponent(Self.defaultTokensFileName)
            if FileManager.default.fileExists(atPath: tokensURL.path) {
                return .ready(localURL: modelURL)
            }
            return .missing(expectedURL: tokensURL)
        }

        // Default location: both must exist.
        if let modelURL = try? defaultModelURL(),
            let tokensURL = try? defaultTokensURL(),
            FileManager.default.fileExists(atPath: modelURL.path),
            FileManager.default.fileExists(atPath: tokensURL.path)
        {
            return .ready(localURL: modelURL)
        }

        let candidate = configuration.sherpaOnnxSenseVoiceModelPath.flatMap {
            $0.isEmpty ? nil : URL(fileURLWithPath: $0)
        }
        return .missing(expectedURL: candidate)
    }

    nonisolated func resolvedModelURL() throws -> URL {
        switch status() {
        case .ready(let url): return url
        case .missing(let expected): throw SenseVoiceError.modelMissing(expectedURL: expected)
        case .runtimeUnavailable: throw SenseVoiceError.runtimeUnavailable
        }
    }

    nonisolated func installDefaultModel(
        downloadProgress: @escaping @Sendable (Double, Int64, Int64) -> Void = { _, _, _ in }
    ) async throws {
        let modelURL = try defaultModelURL()
        let tokensURL = try defaultTokensURL()
        let fileManager = FileManager.default

        // Tokens first — it's tiny and a model without tokens is unusable anyway.
        if !fileManager.fileExists(atPath: tokensURL.path) {
            let progressSink = LocalWhisperDownloadProgressSink(handler: downloadProgress)
            let downloaded = try await downloadProvider(Self.defaultTokensDownloadURL, progressSink)
            if fileManager.fileExists(atPath: tokensURL.path) {
                try fileManager.removeItem(at: tokensURL)
            }
            try fileManager.moveItem(at: downloaded, to: tokensURL)
        }

        if !fileManager.fileExists(atPath: modelURL.path) {
            let progressSink = LocalWhisperDownloadProgressSink(handler: downloadProgress)
            let downloaded = try await downloadProvider(Self.defaultModelDownloadURL, progressSink)
            if fileManager.fileExists(atPath: modelURL.path) {
                try fileManager.removeItem(at: modelURL)
            }
            try fileManager.moveItem(at: downloaded, to: modelURL)
        }

        downloadProgress(1.0, 0, 0)
    }

    nonisolated func statusMessage() -> String {
        switch status() {
        case .ready(let url):
            return "Sherpa-ONNX SenseVoice model is available at \(url.path)."
        case .missing(let url):
            if let url {
                return "Sherpa-ONNX SenseVoice model not found at \(url.path). Pick a different file in Settings."
            }
            return "Download or pick a Sherpa-ONNX SenseVoice .onnx model file in Settings."
        case .runtimeUnavailable:
            return "Sherpa-ONNX runtime is not linked in this build."
        }
    }

    nonisolated func needsAttention() -> Bool {
        switch status() {
        case .ready: return false
        case .missing, .runtimeUnavailable: return true
        }
    }

    @discardableResult
    nonisolated func ensureModelsDirectoryExists() throws -> URL {
        let url = try modelsDirectoryProvider()
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    nonisolated private static func defaultDownloadProvider(
        _ url: URL,
        progressSink: LocalWhisperDownloadProgressSink
    ) async throws -> URL {
        let downloader = SherpaOnnxSenseVoiceDownloadCoordinator(
            requestURL: url,
            progressSink: progressSink
        )
        return try await downloader.download()
    }
}

/// Reusable download coordinator with progress reporting for Sherpa-ONNX SenseVoice model files.
private final class SherpaOnnxSenseVoiceDownloadCoordinator: NSObject, URLSessionDownloadDelegate {
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
                "Stet-SherpaOnnxSenseVoice-\(UUID().uuidString)-\(requestURL.lastPathComponent)", isDirectory: false)
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
