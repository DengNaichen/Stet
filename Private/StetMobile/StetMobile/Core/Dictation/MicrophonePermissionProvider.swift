import AVFoundation
import Foundation

protocol MicrophonePermissionProviding: Sendable {
    func requestPermission() async throws
}

enum MicrophonePermissionError: LocalizedError {
    case denied

    var errorDescription: String? {
        "Microphone permission was not granted."
    }
}

struct SystemMicrophonePermissionProvider: MicrophonePermissionProviding {
    func requestPermission() async throws {
        let granted: Bool
        if #available(iOS 17.0, *) {
            granted = await AVAudioApplication.requestRecordPermission()
        } else {
            granted = await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }

        guard granted else { throw MicrophonePermissionError.denied }
    }
}
