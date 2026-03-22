#if os(macOS)
import CoreAudio
import Foundation

enum CaptureError: LocalizedError {
    case noCaptureDeviceAvailable
    case selectedDeviceUnavailable(target: String, available: [String])
    case failedToCreatePCMBuffer
    case failedToReadSampleBuffer(status: OSStatus)
    case unsupportedSampleBufferFormat
    case failedToConfigureSession(reason: String)
    case failedToStartSession(device: String)

    var errorDescription: String? {
        switch self {
        case .noCaptureDeviceAvailable:
            return "No audio capture device is available."
        case .selectedDeviceUnavailable(let target, let available):
            let availableDescription = available.isEmpty ? "none" : available.joined(separator: ", ")
            return "Selected capture device \(target) was unavailable. available=\(availableDescription)"
        case .failedToCreatePCMBuffer:
            return "Failed to create a PCM buffer for macOS capture."
        case .failedToReadSampleBuffer(let status):
            return "Failed to read an audio sample buffer. osstatus=\(status)"
        case .unsupportedSampleBufferFormat:
            return "Received an unsupported macOS audio sample format."
        case .failedToConfigureSession(let reason):
            return "Failed to configure the macOS capture session. reason=\(reason)"
        case .failedToStartSession(let device):
            return "Failed to start the macOS capture session for \(device)."
        }
    }
}
#endif
