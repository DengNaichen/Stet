import Foundation

public protocol ModelStorageConfiguration: Sendable {
    nonisolated var transcriptionEngine: StoredTranscriptionEngine { get }
    nonisolated func saveTranscriptionEngine(_ engine: StoredTranscriptionEngine)
}
