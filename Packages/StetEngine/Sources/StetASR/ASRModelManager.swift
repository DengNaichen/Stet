import Foundation

public enum ASRModelStatus: Equatable {
    case notDownloaded
    case downloading(progress: Double)
    case ready(localURL: URL)
    case error(message: String)

    public static func == (lhs: ASRModelStatus, rhs: ASRModelStatus) -> Bool {
        switch (lhs, rhs) {
        case (.notDownloaded, .notDownloaded): return true
        case (.downloading(let p1), .downloading(let p2)): return p1 == p2
        case (.ready(let u1), .ready(let u2)): return u1 == u2
        case (.error(let m1), .error(let m2)): return m1 == m2
        default: return false
        }
    }
}

public protocol ASRModelManager: Sendable {
    /// Check the status of a specific model (e.g. "SenseVoice", "Whisper-Base")
    func status(for modelName: String) async -> ASRModelStatus
    
    /// Resolve the local file URLs for a model's resources.
    /// Throws if not ready.
    func resolveModelURLs(for modelName: String) async throws -> [String: URL]
    
    /// Start downloading the model if needed.
    func downloadIfNeeded(for modelName: String) async throws
}
