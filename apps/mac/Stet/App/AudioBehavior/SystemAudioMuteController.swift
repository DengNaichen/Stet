#if os(macOS)
import CoreAudio
import Foundation

@MainActor
protocol SystemAudioMuting: AnyObject {
    @discardableResult
    func activateMuteIfNeeded() -> Bool

    func restoreMuteIfNeeded()
}

@MainActor
final class SystemAudioMuteController: SystemAudioMuting {
    private struct ProcessTapSession {
        let tapID: AudioObjectID
        let aggregateDeviceID: AudioObjectID
        let ioProcID: AudioDeviceIOProcID
    }

    private var processTapSession: ProcessTapSession?

    @discardableResult
    func activateMuteIfNeeded() -> Bool {
        if processTapSession != nil {
            return true
        }

        guard let bundleID = Bundle.main.bundleIdentifier,
              !bundleID.isEmpty,
              let outputDeviceID = defaultOutputDeviceID(),
              let outputUID = deviceUID(for: outputDeviceID) else {
            AppLogger.warning(
                "Skipping system audio mute because the default output device could not be resolved.",
                category: .dictation
            )
            return false
        }

        let tapDescription = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        tapDescription.uuid = UUID()
        tapDescription.name = "Stet System Audio Mute"
        tapDescription.isPrivate = true
        tapDescription.isProcessRestoreEnabled = true
        tapDescription.bundleIDs = [bundleID]
        tapDescription.muteBehavior = .muted

        var tapID = AudioObjectID(kAudioObjectUnknown)
        let tapCreateStatus = AudioHardwareCreateProcessTap(tapDescription, &tapID)
        guard tapCreateStatus == noErr, tapID != AudioObjectID(kAudioObjectUnknown) else {
            AppLogger.warning(
                "Failed to activate system audio mute. step=create_process_tap, status=\(tapCreateStatus)",
                category: .dictation
            )
            return false
        }

        let aggregateUID = "stet-process-tap-\(tapDescription.uuid.uuidString)"
        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "StetProcessTap",
            kAudioAggregateDeviceUIDKey: aggregateUID,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [
                [
                    kAudioSubDeviceUIDKey: outputUID
                ]
            ],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapDriftCompensationKey: true,
                    kAudioSubTapUIDKey: tapDescription.uuid.uuidString
                ]
            ]
        ]

        var aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
        let aggregateStatus = AudioHardwareCreateAggregateDevice(
            aggregateDescription as CFDictionary,
            &aggregateDeviceID
        )
        guard aggregateStatus == noErr, aggregateDeviceID != AudioObjectID(kAudioObjectUnknown) else {
            AudioHardwareDestroyProcessTap(tapID)
            AppLogger.warning(
                "Failed to activate system audio mute. step=create_aggregate_device, status=\(aggregateStatus)",
                category: .dictation
            )
            return false
        }

        var ioProcID: AudioDeviceIOProcID?
        let ioProcStatus = AudioDeviceCreateIOProcIDWithBlock(
            &ioProcID,
            aggregateDeviceID,
            DispatchQueue.global(qos: .userInitiated)
        ) { _, _, _, _, _ in
            // Keep the tap running without reading its buffers.
        }

        guard ioProcStatus == noErr, let ioProcID else {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            AudioHardwareDestroyProcessTap(tapID)
            AppLogger.warning(
                "Failed to activate system audio mute. step=create_io_proc, status=\(ioProcStatus)",
                category: .dictation
            )
            return false
        }

        let startStatus = AudioDeviceStart(aggregateDeviceID, ioProcID)
        guard startStatus == noErr else {
            AudioDeviceDestroyIOProcID(aggregateDeviceID, ioProcID)
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            AudioHardwareDestroyProcessTap(tapID)
            AppLogger.warning(
                "Failed to activate system audio mute. step=start_device, status=\(startStatus)",
                category: .dictation
            )
            return false
        }

        processTapSession = ProcessTapSession(
            tapID: tapID,
            aggregateDeviceID: aggregateDeviceID,
            ioProcID: ioProcID
        )
        AppLogger.info(
            "Activated system audio mute while dictation is active. outputDeviceID=\(outputDeviceID), aggregateDeviceID=\(aggregateDeviceID)",
            category: .dictation
        )
        return true
    }

    func restoreMuteIfNeeded() {
        guard let session = processTapSession else {
            return
        }

        processTapSession = nil

        AudioDeviceStop(session.aggregateDeviceID, session.ioProcID)
        AudioDeviceDestroyIOProcID(session.aggregateDeviceID, session.ioProcID)
        AudioHardwareDestroyAggregateDevice(session.aggregateDeviceID)
        AudioHardwareDestroyProcessTap(session.tapID)
        AppLogger.info("Restored system audio output after dictation.", category: .dictation)
    }

    private func defaultOutputDeviceID() -> AudioDeviceID? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID = AudioDeviceID(0)
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceID
        )
        guard status == noErr, deviceID != 0 else {
            return nil
        }

        return deviceID
    }

    private func deviceUID(for deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let valuePointer = UnsafeMutableRawPointer.allocate(
            byteCount: MemoryLayout<CFString?>.size,
            alignment: MemoryLayout<CFString?>.alignment
        )
        defer { valuePointer.deallocate() }

        valuePointer.initializeMemory(as: CFString?.self, repeating: nil, count: 1)
        defer { valuePointer.assumingMemoryBound(to: CFString?.self).deinitialize(count: 1) }

        var dataSize = UInt32(MemoryLayout<CFString?>.size)
        let status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            valuePointer
        )
        guard status == noErr else {
            return nil
        }

        guard let value = valuePointer.assumingMemoryBound(to: CFString?.self).pointee else {
            return nil
        }

        return value as String
    }
}
#endif
