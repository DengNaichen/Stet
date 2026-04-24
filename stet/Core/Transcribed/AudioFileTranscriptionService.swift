import Foundation

struct TranscriptionResult: Sendable, Equatable {
    let text: String
    let languageCode: String?
}

protocol AudioFileTranscriptionService: Sendable {
    func prewarm() async throws
    func transcribe(
        audioFileAt fileURL: URL,
        languageCode: String?,
        prompt: String?,
        audioDurationSeconds: TimeInterval?
    ) async throws -> TranscriptionResult
}

extension AudioFileTranscriptionService {
    func prewarm() async throws {}
}
