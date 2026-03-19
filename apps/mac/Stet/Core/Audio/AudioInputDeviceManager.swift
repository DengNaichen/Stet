#if os(macOS)
import CoreAudio
import Foundation

struct AudioInputDevice: Identifiable, Hashable, Sendable {
    let id: AudioDeviceID
    let name: String
}

struct AudioHardwareDevice: Equatable, Sendable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let transportType: UInt32
    let hasInputStream: Bool
    let hasOutputStream: Bool
}

struct DictationInputDeviceSelection: Equatable, Sendable {
    enum Reason: String, Equatable, Sendable {
        case systemDefault
        case bluetoothProfileFallback
        case sharedExternalDeviceFallback
    }

    let device: AudioHardwareDevice
    let reason: Reason
}

enum AudioInputDeviceManager {
    nonisolated static func availableInputDevices() -> [AudioInputDevice] {
        availableHardwareDevices()
            .filter(\.hasInputStream)
            .map { device in
                AudioInputDevice(id: device.id, name: device.name)
            }
            .sorted { lhs, rhs in
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    nonisolated static func defaultInputDeviceID() -> AudioDeviceID? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
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
            AppLogger.warning("Failed to read default input device. status=\(status), deviceID=\(deviceID)")
            return nil
        }

        return deviceID
    }

    nonisolated static func defaultOutputDeviceID() -> AudioDeviceID? {
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
            AppLogger.warning("Failed to read default output device. status=\(status), deviceID=\(deviceID)")
            return nil
        }

        return deviceID
    }

    nonisolated static func defaultInputDevice() -> AudioHardwareDevice? {
        guard let deviceID = defaultInputDeviceID() else {
            return nil
        }

        return hardwareDevice(deviceID: deviceID)
    }

    nonisolated static func defaultOutputDevice() -> AudioHardwareDevice? {
        guard let deviceID = defaultOutputDeviceID() else {
            return nil
        }

        return hardwareDevice(deviceID: deviceID)
    }

    nonisolated static func inputStreamFormat(for deviceID: AudioDeviceID) -> AudioStreamBasicDescription? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamFormat,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var streamFormat = AudioStreamBasicDescription()
        var dataSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &streamFormat
        )
        guard status == noErr,
              streamFormat.mSampleRate > 0,
              streamFormat.mChannelsPerFrame > 0 else {
            AppLogger.warning(
                """
                Failed to read input stream format. \
                deviceID=\(deviceID), \
                status=\(status), \
                sampleRate=\(Int(streamFormat.mSampleRate)), \
                channels=\(streamFormat.mChannelsPerFrame)
                """
            )
            return nil
        }

        return streamFormat
    }

    nonisolated static func defaultInputStreamFormat() -> AudioStreamBasicDescription? {
        guard let deviceID = defaultInputDeviceID() else {
            return nil
        }

        return inputStreamFormat(for: deviceID)
    }

    nonisolated static func preferredInputDeviceForDictation() -> DictationInputDeviceSelection? {
        preferredInputDeviceForDictation(
            defaultInputDevice: defaultInputDevice(),
            defaultOutputDevice: defaultOutputDevice(),
            availableInputDevices: availableHardwareDevices().filter(\.hasInputStream)
        )
    }

    nonisolated static func preferredInputDeviceForDictation(
        defaultInputDevice: AudioHardwareDevice?,
        defaultOutputDevice: AudioHardwareDevice?,
        availableInputDevices: [AudioHardwareDevice]
    ) -> DictationInputDeviceSelection? {
        guard let defaultInputDevice else {
            return nil
        }

        guard let fallbackDevice = availableInputDevices.first(where: {
            $0.transportType == kAudioDeviceTransportTypeBuiltIn && $0.id != defaultInputDevice.id
        }) else {
            return DictationInputDeviceSelection(
                device: defaultInputDevice,
                reason: .systemDefault
            )
        }

        if isBluetoothTransport(defaultInputDevice.transportType) {
            return DictationInputDeviceSelection(
                device: fallbackDevice,
                reason: .bluetoothProfileFallback
            )
        }

        if let defaultOutputDevice,
           defaultInputDevice.transportType != kAudioDeviceTransportTypeBuiltIn,
           (defaultInputDevice.id == defaultOutputDevice.id ||
            defaultInputDevice.uid == defaultOutputDevice.uid) {
            return DictationInputDeviceSelection(
                device: fallbackDevice,
                reason: .sharedExternalDeviceFallback
            )
        }

        return DictationInputDeviceSelection(
            device: defaultInputDevice,
            reason: .systemDefault
        )
    }

    nonisolated static func isBluetoothTransport(_ transportType: UInt32) -> Bool {
        transportType == kAudioDeviceTransportTypeBluetooth ||
        transportType == kAudioDeviceTransportTypeBluetoothLE
    }

    nonisolated private static func hasInputStream(deviceID: AudioDeviceID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &dataSize)
        return status == noErr && dataSize > 0
    }

    nonisolated private static func hasOutputStream(deviceID: AudioDeviceID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &dataSize)
        return status == noErr && dataSize > 0
    }

    nonisolated private static func availableHardwareDevices() -> [AudioHardwareDevice] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let sizeStatus = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )
        guard sizeStatus == noErr, dataSize > 0 else {
            AppLogger.warning(
                "Failed to query audio devices. status=\(sizeStatus), dataSize=\(dataSize)"
            )
            return []
        }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = Array(repeating: AudioDeviceID(0), count: deviceCount)
        let listStatus = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceIDs
        )
        guard listStatus == noErr else {
            AppLogger.warning("Failed to load audio device list. status=\(listStatus)")
            return []
        }

        return deviceIDs.compactMap(hardwareDevice(deviceID:))
    }

    nonisolated private static func hardwareDevice(deviceID: AudioDeviceID) -> AudioHardwareDevice? {
        guard let name = deviceName(deviceID: deviceID),
              !name.isEmpty,
              let uid = deviceUID(deviceID: deviceID) else {
            return nil
        }

        return AudioHardwareDevice(
            id: deviceID,
            uid: uid,
            name: name,
            transportType: deviceTransportType(deviceID: deviceID) ?? kAudioDeviceTransportTypeUnknown,
            hasInputStream: hasInputStream(deviceID: deviceID),
            hasOutputStream: hasOutputStream(deviceID: deviceID)
        )
    }

    nonisolated private static func deviceUID(deviceID: AudioDeviceID) -> String? {
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
        guard status == noErr,
              let value = valuePointer.assumingMemoryBound(to: CFString?.self).pointee else {
            return nil
        }

        return value as String
    }

    nonisolated private static func deviceTransportType(deviceID: AudioDeviceID) -> UInt32? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var transportType = UInt32(0)
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &transportType
        )
        guard status == noErr else {
            return nil
        }

        return transportType
    }

    nonisolated private static func deviceName(deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var buffer = [CChar](repeating: 0, count: 256)
        var dataSize = UInt32(buffer.count * MemoryLayout<CChar>.size)
        let status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, &buffer)
        guard status == noErr else { return nil }
        return String(cString: buffer)
    }
}
#endif
