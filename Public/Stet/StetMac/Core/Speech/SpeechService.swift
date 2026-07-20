import Foundation

protocol SpeechService: Sendable {
    func startRecording() async throws
    func startRecordingAndActivate() async throws
    func activateRecordingWindow() async throws
    func stopRecording(
        onCaptureStopped: (@Sendable () async -> Void)?
    ) async throws -> String
    func cancelRecording() async
    func prewarm() async
}

extension SpeechService {
    func stopRecording() async throws -> String {
        try await stopRecording(onCaptureStopped: nil)
    }
}
