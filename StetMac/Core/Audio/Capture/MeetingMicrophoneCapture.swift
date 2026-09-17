#if os(macOS)
    @preconcurrency import AVFoundation
    import CoreMedia
    import Foundation

    nonisolated final class MeetingMicrophoneCapture: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate,
        @unchecked Sendable
    {
        private let sink: MeetingAudioRecordingSink
        private let queue = DispatchQueue(label: "Stet.MeetingAudio.microphone", qos: .userInitiated)
        private var resources: CaptureResources?
        private var observers: [NSObjectProtocol] = []

        init(sink: MeetingAudioRecordingSink) { self.sink = sink }

        func start(device: AudioHardwareDevice?) throws {
            // Resolve exactly the selected device. An output/headset change must not silently pick another input.
            let captureDevice: AVCaptureDevice
            if let device {
                guard
                    let selected = MacCaptureAudioDevicePlanner.availableCaptureDevices()
                        .first(where: { $0.uniqueID == device.uid })
                else {
                    throw MeetingRecordingError.failed("The selected microphone (\(device.name)) is unavailable.")
                }
                captureDevice = selected
            } else {
                guard let selected = AVCaptureDevice.default(for: .audio) else {
                    throw MeetingRecordingError.failed("No microphone is available.")
                }
                captureDevice = selected
            }
            let resources = try MacCaptureAudioSessionFactory.makeCaptureResources(
                for: captureDevice, delegate: self, queue: queue)
            self.resources = resources
            let sink = self.sink
            for name in [AVCaptureSession.runtimeErrorNotification, AVCaptureSession.wasInterruptedNotification] {
                observers.append(
                    NotificationCenter.default.addObserver(forName: name, object: resources.session, queue: nil) { _ in
                        sink.reportFailure("Microphone recording was interrupted. The audio already recorded was kept.")
                    })
            }
            resources.session.startRunning()
            guard resources.session.isRunning else {
                stop()
                throw MeetingRecordingError.failed("The selected microphone could not start recording.")
            }
        }

        func stop() {
            for observer in observers { NotificationCenter.default.removeObserver(observer) }
            observers.removeAll()
            resources?.session.stopRunning()
            resources?.output.setSampleBufferDelegate(nil, queue: nil)
            queue.sync {}
            resources = nil
        }

        func captureOutput(
            _ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection
        ) {
            do {
                let buffer = try MacCaptureAudioSampleBufferConverter.pcmBuffer(from: sampleBuffer)
                let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                sink.receive(buffer, source: .microphone, hostTime: timestamp.seconds)
            } catch { sink.reportFailure("Could not read microphone audio: \(error.localizedDescription)") }
        }

        func captureOutput(
            _ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection
        ) {
            sink.reportFailure("Microphone audio was dropped. Recording stopped and existing audio was kept.")
        }
    }
#endif
