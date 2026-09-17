#if os(macOS)
    @preconcurrency import AVFoundation
    import CoreAudio
    import Foundation

    /// Control operations and property listeners share controlQueue. Audio callbacks only copy/enqueue.
    nonisolated final class MeetingSystemAudioCapture: @unchecked Sendable {
        private let controlQueue: DispatchQueue
        private let audioQueue = DispatchQueue(label: "Stet.MeetingAudio.system", qos: .userInitiated)
        private let sink: MeetingAudioRecordingSink
        private var tapID = AudioObjectID(kAudioObjectUnknown)
        private var aggregateID = AudioObjectID(kAudioObjectUnknown)
        private var ioProc: AudioDeviceIOProcID?
        private var listeners: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
        private var running = false

        init(controlQueue: DispatchQueue, sink: MeetingAudioRecordingSink) {
            self.controlQueue = controlQueue
            self.sink = sink
        }

        func start() throws {
            do {
                try startHardware()
                running = true
                try listen(
                    to: AudioObjectID(kAudioObjectSystemObject), selector: kAudioHardwarePropertyDefaultOutputDevice)
                if let outputID = AudioInputDeviceManager.defaultOutputDeviceID() {
                    try listen(to: outputID, selector: kAudioDevicePropertyNominalSampleRate)
                }
            } catch {
                stop()
                throw error
            }
        }

        func stop() {
            running = false
            for (object, originalAddress, block) in listeners {
                var address = originalAddress
                AudioObjectRemovePropertyListenerBlock(object, &address, controlQueue, block)
            }
            listeners.removeAll()
            if let ioProc {
                AudioDeviceStop(aggregateID, ioProc)
                AudioDeviceDestroyIOProcID(aggregateID, ioProc)
                self.ioProc = nil
            }
            // No callback may enqueue data after the recorder drains the sink.
            audioQueue.sync {}
            if aggregateID != kAudioObjectUnknown {
                AudioHardwareDestroyAggregateDevice(aggregateID)
                aggregateID = AudioObjectID(kAudioObjectUnknown)
            }
            if tapID != kAudioObjectUnknown {
                AudioHardwareDestroyProcessTap(tapID)
                tapID = AudioObjectID(kAudioObjectUnknown)
            }
        }

        private func startHardware() throws {
            guard AudioInputDeviceManager.defaultOutputDeviceID() != nil else {
                throw MeetingRecordingError.failed("No system audio output device is available.")
            }
            let excludedProcesses = Self.currentAudioProcess().map { [$0] } ?? []
            let description = CATapDescription(stereoGlobalTapButExcludeProcesses: excludedProcesses)
            description.uuid = UUID()
            description.name = "Stet Meeting System Audio"
            description.isPrivate = true
            description.muteBehavior = .unmuted
            if #available(macOS 26.0, *), let bundleID = Bundle.main.bundleIdentifier {
                description.bundleIDs = [bundleID]
            }
            try check(AudioHardwareCreateProcessTap(description, &tapID), operation: "start system audio capture")
            var streamDescription = AudioStreamBasicDescription()
            var formatAddress = Self.address(kAudioTapPropertyFormat)
            var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            try check(
                AudioObjectGetPropertyData(tapID, &formatAddress, 0, nil, &size, &streamDescription),
                operation: "read the system audio format"
            )
            guard let format = AVAudioFormat(streamDescription: &streamDescription) else {
                throw MeetingRecordingError.failed("The system audio format is unsupported.")
            }
            let deviceDescription: [String: Any] = [
                kAudioAggregateDeviceNameKey: "Stet Meeting Capture",
                kAudioAggregateDeviceUIDKey: "\(Bundle.main.bundleIdentifier ?? "com.stet").meeting-system-audio",
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceTapAutoStartKey: true,
                // A physical output may also expose headset microphone channels. Only the tap
                // belongs here; the selected microphone has its own AVCaptureSession.
                kAudioAggregateDeviceTapListKey: [
                    [
                        kAudioSubTapUIDKey: description.uuid.uuidString,
                        kAudioSubTapDriftCompensationKey: true,
                    ]
                ],
            ]
            try check(
                AudioHardwareCreateAggregateDevice(deviceDescription as CFDictionary, &aggregateID),
                operation: "prepare system audio recording"
            )
            let sink = self.sink
            try check(
                AudioDeviceCreateIOProcIDWithBlock(&ioProc, aggregateID, audioQueue) { now, input, inputTime, _, _ in
                    guard
                        UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
                            .contains(where: { $0.mDataByteSize > 0 })
                    else { return }
                    let stamp = inputTime.pointee
                    let hostTime = stamp.mFlags.contains(.hostTimeValid) ? stamp.mHostTime : now.pointee.mHostTime
                    guard hostTime > 0,
                        let buffer = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: input, deallocator: nil)
                    else {
                        sink.reportFailure("System audio supplied an invalid buffer or timestamp.")
                        return
                    }
                    sink.receive(buffer, source: .system, hostTime: AVAudioTime.seconds(forHostTime: hostTime))
                },
                operation: "connect system audio recording"
            )
            guard let ioProc else { throw MeetingRecordingError.failed("Could not connect system audio recording.") }
            try check(AudioDeviceStart(aggregateID, ioProc), operation: "record system audio")
        }

        private func listen(to object: AudioObjectID, selector: AudioObjectPropertySelector) throws {
            var address = Self.address(selector)
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                guard let self, self.running else { return }
                // A call can change the output route or Bluetooth sample rate. The microphone stays untouched.
                self.stop()
                do { try self.start() } catch {
                    self.sink.reportFailure(
                        "System audio could not resume after the output changed: \(error.localizedDescription)")
                }
            }
            try check(
                AudioObjectAddPropertyListenerBlock(object, &address, controlQueue, block),
                operation: "monitor system audio device changes"
            )
            listeners.append((object, address, block))
        }

        private func check(_ status: OSStatus, operation: String) throws {
            guard status != noErr else { return }
            let permissionHint =
                operation == "start system audio capture" || operation == "record system audio"
                ? " Check Stet's access in System Settings → Privacy & Security → Screen & System Audio Recording."
                : ""
            throw MeetingRecordingError.failed("Could not \(operation) (\(status)).\(permissionHint)")
        }

        private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
            AudioObjectPropertyAddress(
                mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain
            )
        }

        private static func currentAudioProcess() -> AudioObjectID? {
            var pid = ProcessInfo.processInfo.processIdentifier
            var process = AudioObjectID(kAudioObjectUnknown)
            var address = address(kAudioHardwarePropertyTranslatePIDToProcessObject)
            var size = UInt32(MemoryLayout<AudioObjectID>.size)
            let status = AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject), &address,
                UInt32(MemoryLayout<pid_t>.size), &pid, &size, &process
            )
            return status == noErr && process != kAudioObjectUnknown ? process : nil
        }
    }
#endif
