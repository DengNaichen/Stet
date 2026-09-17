#if os(macOS)
    @preconcurrency import AVFoundation
    import AppKit
    import Foundation

    nonisolated protocol MeetingAudioRecording: Sendable {
        func start(in directory: URL, onFailure: @escaping @Sendable (String) -> Void) async throws
        func stop() async throws -> MeetingAudioRecordingResult
    }

    nonisolated final class MacMeetingAudioRecorder: @unchecked Sendable, MeetingAudioRecording {
        private let controlQueue = DispatchQueue(label: "Stet.MeetingAudio.control", qos: .userInitiated)
        private var microphone: MeetingMicrophoneCapture?
        private var systemAudio: MeetingSystemAudioCapture?
        private var sink: MeetingAudioRecordingSink?
        private var sleepObservation: (NotificationCenter, NSObjectProtocol)?

        func start(in directory: URL, onFailure: @escaping @Sendable (String) -> Void) async throws {
            guard await AVCaptureDevice.requestAccess(for: .audio) else {
                throw MeetingRecordingError.failed(
                    "Allow Stet to use the microphone in System Settings → Privacy & Security → Microphone.")
            }
            let (device, workspaceNotifications) = await MainActor.run {
                AudioDeviceSelectionManager.shared.refreshDevices()
                return (
                    AudioDeviceSelectionManager.shared.currentRecordingDevice(), NSWorkspace.shared.notificationCenter
                )
            }
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                controlQueue.async {
                    do {
                        let sink = try MeetingAudioRecordingSink(
                            directory: directory, startTime: ProcessInfo.processInfo.systemUptime, onFailure: onFailure
                        )
                        self.sink = sink
                        let observer = workspaceNotifications.addObserver(
                            forName: NSWorkspace.willSleepNotification, object: nil, queue: nil
                        ) { _ in
                            sink.reportFailure(
                                "Recording stopped because the Mac is going to sleep. Existing audio was kept.")
                        }
                        self.sleepObservation = (workspaceNotifications, observer)
                        let systemAudio = MeetingSystemAudioCapture(controlQueue: self.controlQueue, sink: sink)
                        self.systemAudio = systemAudio
                        try systemAudio.start()
                        let microphone = MeetingMicrophoneCapture(sink: sink)
                        self.microphone = microphone
                        try microphone.start(device: device)
                        sink.startMonitoring()
                        continuation.resume()
                    } catch {
                        self.removeSleepObservation()
                        self.microphone?.stop()
                        self.systemAudio?.stop()
                        self.microphone = nil
                        self.systemAudio = nil
                        let sink = self.sink
                        self.sink = nil
                        Task {
                            sink?.reportFailure(error.localizedDescription)
                            _ = try? await sink?.finish(at: ProcessInfo.processInfo.systemUptime)
                            continuation.resume(throwing: error)
                        }
                    }
                }
            }
        }

        func stop() async throws -> MeetingAudioRecordingResult {
            let stopped: (MeetingAudioRecordingSink, TimeInterval) = try await withCheckedThrowingContinuation {
                continuation in
                controlQueue.async {
                    let stopTime = ProcessInfo.processInfo.systemUptime
                    self.removeSleepObservation()
                    self.microphone?.stop()
                    self.systemAudio?.stop()
                    self.microphone = nil
                    self.systemAudio = nil
                    guard let sink = self.sink else {
                        continuation.resume(throwing: MeetingRecordingError.failed("No meeting recording is active."))
                        return
                    }
                    self.sink = nil
                    continuation.resume(returning: (sink, stopTime))
                }
            }
            return try await stopped.0.finish(at: stopped.1)
        }

        private func removeSleepObservation() {
            if let (center, observer) = sleepObservation { center.removeObserver(observer) }
            sleepObservation = nil
        }
    }
#endif
