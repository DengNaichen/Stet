import Foundation

protocol AudioFileTranscriptionService: Sendable {
    func prewarm() async throws
    func transcribe(
        audioFileAt fileURL: URL,
        languageCode: String?,
        prompt: String?,
        audioDurationSeconds: TimeInterval?
    ) async throws -> String
}

extension AudioFileTranscriptionService {
    func prewarm() async throws {}
}
