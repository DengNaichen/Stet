import Foundation

struct TranscriptionResult: Sendable, Equatable {
    let text: String
    let languageCode: String?
}

nonisolated protocol AudioFileTranscriptionService: Sendable {
    func isPrewarmed() async -> Bool
    func prewarm() async throws
    func transcribe(
        audioFileAt fileURL: URL,
        languageCode: String?,
        prompt: String?,
        audioDurationSeconds: TimeInterval?
    ) async throws -> TranscriptionResult
}

extension AudioFileTranscriptionService {
    func isPrewarmed() async -> Bool { false }
    func prewarm() async throws {}
}
