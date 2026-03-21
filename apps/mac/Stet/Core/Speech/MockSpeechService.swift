import Foundation

struct MockSpeechService: SpeechService {
    func startRecording() async throws {
        try await Task.sleep(nanoseconds: 150_000_000)
    }

    func startRecordingAndActivate() async throws {
        try await startRecording()
        try await activateRecordingWindow()
    }

    func activateRecordingWindow() async throws {}

    func stopRecording() async throws -> String {
        try await Task.sleep(nanoseconds: 900_000_000)
        return "This is a mock transcription from the speech service."
    }

    func cancelRecording() async {
        // No-op for the mock service.
    }

    func prewarm() async {}
}
