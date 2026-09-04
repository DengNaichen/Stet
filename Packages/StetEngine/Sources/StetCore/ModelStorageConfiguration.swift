import Foundation

public protocol ModelStorageConfiguration: Sendable {
    nonisolated var localWhisperModelPath: String? { get }
    nonisolated func saveLocalWhisperModelPath(_ path: String?)

    nonisolated var transcriptionEngine: StoredTranscriptionEngine { get }
    nonisolated func saveTranscriptionEngine(_ engine: StoredTranscriptionEngine)
}
