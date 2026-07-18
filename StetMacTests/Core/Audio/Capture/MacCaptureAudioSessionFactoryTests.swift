#if os(macOS)
    import AVFoundation
    import Testing

    @testable import Stet

    @Suite("Mac Capture Audio Session Factory")
    struct MacCaptureAudioSessionFactoryTests {
        @Test func captureResourcesContainsAllComponents() throws {
            let devices = MacCaptureAudioDevicePlanner.availableCaptureDevices()
            guard let device = devices.first else {
                return
            }

            let queue = DispatchQueue(label: "test.capture")
            let delegate = TestCaptureDelegate()

            let resources = try MacCaptureAudioSessionFactory.makeCaptureResources(
                for: device,
                delegate: delegate,
                queue: queue
            )

            #expect(resources.session.inputs.count == 1)
            #expect(resources.session.outputs.count == 1)
            #expect(resources.session.outputs.first === resources.output)
            #expect(resources.device == device)

            let input = try #require(resources.session.inputs.first as? AVCaptureDeviceInput)
            #expect(input.device.uniqueID == device.uniqueID)
        }
    }

    private final class TestCaptureDelegate: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
        func captureOutput(
            _ output: AVCaptureOutput,
            didOutput sampleBuffer: CMSampleBuffer,
            from connection: AVCaptureConnection
        ) {
        }
    }
#endif
