#if os(macOS)
import Testing

@testable import Stet

@Suite("Capture Error")
struct CaptureErrorTests {
    @Test func noCaptureDeviceAvailableHasCorrectDescription() {
        let error = CaptureError.noCaptureDeviceAvailable

        #expect(error.errorDescription == "No audio capture device is available.")
    }

    @Test func selectedDeviceUnavailableIncludesDeviceInfo() {
        let error = CaptureError.selectedDeviceUnavailable(
            target: "USB Mic",
            available: ["Built-in", "AirPods"]
        )

        #expect(error.errorDescription == "Selected capture device USB Mic was unavailable. available=Built-in, AirPods")
    }

    @Test func failedToReadSampleBufferIncludesStatus() {
        let error = CaptureError.failedToReadSampleBuffer(status: -50)

        #expect(error.errorDescription == "Failed to read an audio sample buffer. osstatus=-50")
    }

    @Test func failedToConfigureSessionIncludesReason() {
        let error = CaptureError.failedToConfigureSession(reason: "cannot add input")

        #expect(error.errorDescription == "Failed to configure the macOS capture session. reason=cannot add input")
    }

    @Test func failedToStartSessionIncludesDevice() {
        let error = CaptureError.failedToStartSession(device: "USB Microphone")

        #expect(error.errorDescription == "Failed to start the macOS capture session for USB Microphone.")
    }

    @Test func failedToCreatePCMBufferHasCorrectDescription() {
        let error = CaptureError.failedToCreatePCMBuffer

        #expect(error.errorDescription == "Failed to create a PCM buffer for macOS capture.")
    }

    @Test func unsupportedSampleBufferFormatHasCorrectDescription() {
        let error = CaptureError.unsupportedSampleBufferFormat

        #expect(error.errorDescription == "Received an unsupported macOS audio sample format.")
    }
}
#endif
