import Foundation

protocol SpeechService: Sendable {
    func startRecording() async throws
    func startRecordingAndActivate() async throws
    func activateRecordingWindow() async throws
    func stopRecording() async throws -> String
    func cancelRecording() async
    func prewarm() async
}
