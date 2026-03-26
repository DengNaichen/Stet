import AVFoundation
import Foundation

/// Default implementation of `MicrophoneTestService` for microphone testing.
@MainActor
final class DefaultMicrophoneTestService: NSObject, MicrophoneTestService, AVAudioPlayerDelegate {
    static let shared = DefaultMicrophoneTestService(captureService: MacAudioCaptureService())

    private let captureService: any AudioCaptureService & AudioLevelSource
    private var player: AVAudioPlayer?
    private var playbackContinuation: CheckedContinuation<Void, Error>?

    init(captureService: any AudioCaptureService & AudioLevelSource) {
        self.captureService = captureService
        super.init()
    }

    func startRecording() async throws {
        stopPlayback()
        try await captureService.startRecording()
        try await captureService.activateRecordingWindow()
    }

    func stopRecording() async throws -> URL {
        let result = try await captureService.stopRecording()
        return result.url
    }

    func playRecording(at url: URL) async throws {
        stopPlayback()

        let player = try AVAudioPlayer(contentsOf: url)
        self.player = player
        player.delegate = self
        player.prepareToPlay()

        guard player.play() else {
            self.player = nil
            throw MicrophoneTestServiceError.playbackFailed
        }

        try await withCheckedThrowingContinuation { continuation in
            playbackContinuation = continuation
        }
    }

    func stopPlayback() {
        guard player != nil || playbackContinuation != nil else {
            return
        }

        player?.stop()
        player = nil
        finishPlayback()
    }

    func makeAudioLevelStream() async -> AsyncStream<Double> {
        await captureService.makeAudioLevelStream()
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.player = nil
            self.finishPlayback()
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            self.player = nil
            self.finishPlayback(throwing: error ?? MicrophoneTestServiceError.playbackFailed)
        }
    }

    private func finishPlayback(throwing error: Error? = nil) {
        guard let continuation = playbackContinuation else {
            return
        }

        playbackContinuation = nil
        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume(returning: ())
        }
    }
}

/// Errors that can occur during audio testing.
enum MicrophoneTestServiceError: Error, LocalizedError {
    case playbackFailed

    var errorDescription: String? {
        switch self {
        case .playbackFailed:
            return "Failed to play recording"
        }
    }
}
