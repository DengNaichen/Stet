#if os(macOS)
import Foundation

enum MacCaptureBackend: String, Sendable {
    case nativeVoiceProcessing = "AVAudioEngine+VoiceProcessing"
    case nativeRawEngine = "AVAudioEngine"
    case avCapture = "AVCaptureSession"
}

struct MacCaptureAttemptPlan: Sendable {
    let candidate: MacRecordingInputDeviceResolver.InputDeviceCandidate
    let backend: MacCaptureBackend
    let inputDevice: AudioHardwareDevice?
    let explicitBinding: Bool
    let voiceProcessingRequested: Bool
    let voiceProcessingFallbackReason: String?
}

enum MacCaptureRouteNegotiator {
    nonisolated static func attemptPlans(
        for candidate: MacRecordingInputDeviceResolver.InputDeviceCandidate
    ) -> [MacCaptureAttemptPlan] {
        let explicitBinding = candidate.device.map(shouldBindExplicitly(to:)) ?? false

        if explicitBinding {
            return [
                MacCaptureAttemptPlan(
                    candidate: candidate,
                    backend: .nativeRawEngine,
                    inputDevice: candidate.device,
                    explicitBinding: true,
                    voiceProcessingRequested: false,
                    voiceProcessingFallbackReason: "voice processing disabled for explicitly bound route"
                ),
                MacCaptureAttemptPlan(
                    candidate: candidate,
                    backend: .avCapture,
                    inputDevice: candidate.device,
                    explicitBinding: false,
                    voiceProcessingRequested: false,
                    voiceProcessingFallbackReason: "input-only avcapture capture"
                ),
            ]
        }

        return [
            MacCaptureAttemptPlan(
                candidate: candidate,
                backend: .nativeVoiceProcessing,
                inputDevice: candidate.device,
                explicitBinding: false,
                voiceProcessingRequested: true,
                voiceProcessingFallbackReason: nil
            ),
            MacCaptureAttemptPlan(
                candidate: candidate,
                backend: .nativeRawEngine,
                inputDevice: candidate.device,
                explicitBinding: false,
                voiceProcessingRequested: false,
                voiceProcessingFallbackReason: "voice processing disabled after route negotiation fallback"
            ),
            MacCaptureAttemptPlan(
                candidate: candidate,
                backend: .avCapture,
                inputDevice: candidate.device,
                explicitBinding: false,
                voiceProcessingRequested: false,
                voiceProcessingFallbackReason: "input-only avcapture capture"
            ),
        ]
    }

    nonisolated static func shouldBindExplicitly(to device: AudioHardwareDevice) -> Bool {
        if let defaultInputDevice = AudioInputDeviceManager.defaultInputDevice(),
           defaultInputDevice.uid == device.uid,
           !device.isBluetooth {
            return false
        }

        return true
    }

    nonisolated static func describe(_ attempt: MacCaptureAttemptPlan) -> String {
        """
        backend=\(attempt.backend.rawValue) \
        candidateReason=\(attempt.candidate.reason.rawValue) \
        device=\(attempt.inputDevice?.name ?? "systemDefault") \
        explicitBinding=\(attempt.explicitBinding) \
        voiceProcessingRequested=\(attempt.voiceProcessingRequested)
        """
    }
}
#endif
