import Foundation

protocol SpeechService: Sendable {
    func startRecording() async throws
    func stopRecording() async throws -> String
    func cancelRecording() async
}
