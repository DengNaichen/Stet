#if os(macOS)
@preconcurrency import AVFoundation
import Foundation

struct CaptureResources {
    let session: AVCaptureSession
    let output: AVCaptureAudioDataOutput
    let device: AVCaptureDevice
}

enum MacCaptureAudioSessionFactory {
    nonisolated static func makeCaptureResources(
        for device: AVCaptureDevice,
        delegate: any AVCaptureAudioDataOutputSampleBufferDelegate,
        queue: DispatchQueue
    ) throws -> CaptureResources {
        let session = AVCaptureSession()
        let input = try AVCaptureDeviceInput(device: device)
        let output = AVCaptureAudioDataOutput()
        output.setSampleBufferDelegate(delegate, queue: queue)

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        guard session.canAddInput(input) else {
            throw CaptureError.failedToConfigureSession(reason: "cannot add input \(device.localizedName)")
        }
        session.addInput(input)

        guard session.canAddOutput(output) else {
            throw CaptureError.failedToConfigureSession(reason: "cannot add audio output")
        }
        session.addOutput(output)

        return CaptureResources(
            session: session,
            output: output,
            device: device
        )
    }
}
#endif
