import Foundation

protocol AudioCaptureService: Sendable {
    func startRecording() async throws
    func activateRecordingWindow() async throws
    func stopRecording() async throws -> (url: URL, duration: TimeInterval?)
    func cancelRecording() async
}
