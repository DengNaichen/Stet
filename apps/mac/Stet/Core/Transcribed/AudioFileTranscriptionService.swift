import Foundation

protocol AudioFileTranscriptionService: Sendable {
    func transcribe(
        audioFileAt fileURL: URL,
        languageCode: String?,
        prompt: String?,
        audioDurationSeconds: TimeInterval?
    ) async throws -> String
}
