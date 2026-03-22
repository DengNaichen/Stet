#if os(macOS)
import CoreAudio
import Testing

@testable import Stet

@MainActor
@Suite("Mac Capture Route Negotiator")
struct MacCaptureRouteNegotiatorTests {
    @Test func explicitBindingRouteSkipsVoiceProcessingPlan() {
        let usbMic = AudioHardwareDevice(
            id: 42,
            uid: "usb-mic",
            name: "USB Mic",
            transportType: kAudioDeviceTransportTypeUSB
        )
        let candidate = MacRecordingInputDeviceResolver.InputDeviceCandidate(
            device: usbMic,
            reason: .selected
        )

        let attempts = MacCaptureRouteNegotiator.attemptPlans(for: candidate)

        #expect(attempts.map(\.backend) == [.nativeRawEngine, .avCapture])
        #expect(attempts.allSatisfy { !$0.voiceProcessingRequested })
        #expect(attempts.first?.explicitBinding == true)
    }

    @Test func defaultRouteIncludesVoiceProcessingPlan() {
        let candidate = MacRecordingInputDeviceResolver.InputDeviceCandidate(
            device: nil,
            reason: .noExplicitDeviceFallback
        )

        let attempts = MacCaptureRouteNegotiator.attemptPlans(for: candidate)

        #expect(attempts.map(\.backend) == [.nativeVoiceProcessing, .nativeRawEngine, .avCapture])
        #expect(attempts.first?.voiceProcessingRequested == true)
        #expect(attempts.first?.explicitBinding == false)
    }
}
#endif
