import Foundation

/// Protocol for microphone testing functionality
@MainActor
protocol MicrophoneTestService: AnyObject, AudioLevelSource {
    /// Start recording a test audio sample
    func startRecording() async throws

    /// Stop recording and return the URL of the recorded file
    func stopRecording() async throws -> URL

    /// Play a recording at the given URL
    func playRecording(at url: URL) async throws

    /// Stop any ongoing playback
    func stopPlayback()
}
