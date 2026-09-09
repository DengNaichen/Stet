import Foundation

/// Outcome of a completed capture: raw ASR text plus the post-rewrite string that
/// should be delivered. History needs both; callers that only paste text use `text`.
struct SpeechTranscriptionResult: Equatable, Sendable, ExpressibleByStringLiteral {
    /// ASR output before rewrite. When rewrite did not run (or failed), this is the
    /// delivered text after local punctuation cleanup, so it matches `text`.
    let rawText: String
    /// Text after rewrite and any local punctuation cleanup. Same as `rawText` when rewrite did not run.
    let text: String
    /// True when a rewrite service produced `text` (even if it happens to equal `rawText`).
    let wasRewritten: Bool

    init(rawText: String, text: String, wasRewritten: Bool) {
        self.rawText = rawText
        self.text = text
        self.wasRewritten = wasRewritten
    }

    init(_ text: String) {
        self.rawText = text
        self.text = text
        self.wasRewritten = false
    }

    init(stringLiteral value: String) {
        self.init(value)
    }
}

protocol SpeechService: Sendable {
    func startRecording() async throws
    func startRecordingAndActivate() async throws
    func activateRecordingWindow() async throws
    func stopRecording(
        onCaptureStopped: (@Sendable () async -> Void)?
    ) async throws -> SpeechTranscriptionResult
    func cancelRecording() async
    func prewarm() async
}

extension SpeechService {
    func stopRecording() async throws -> SpeechTranscriptionResult {
        try await stopRecording(onCaptureStopped: nil)
    }
}
