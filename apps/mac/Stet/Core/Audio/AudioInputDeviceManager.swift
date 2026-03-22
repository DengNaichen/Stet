#if os(macOS)
import CoreAudio
import Foundation

enum AudioInputDeviceManager {
    nonisolated static func defaultInputDeviceID() -> AudioDeviceID? {
        defaultDeviceID(selector: kAudioHardwarePropertyDefaultInputDevice)
    }

    nonisolated static func defaultOutputDeviceID() -> AudioDeviceID? {
        defaultDeviceID(selector: kAudioHardwarePropertyDefaultOutputDevice)
    }

    nonisolated static func defaultInputDevice() -> AudioHardwareDevice? {
        guard let deviceID = defaultInputDeviceID() else {
            return nil
        }

        return hardwareDevice(deviceID: deviceID)
    }

    nonisolated static func builtInInputDevice() -> AudioHardwareDevice? {
        allInputDevices().first(where: \.isBuiltIn)
    }

    nonisolated static func defaultOutputDevice() -> AudioHardwareDevice? {
        guard let deviceID = defaultOutputDeviceID() else {
            return nil
        }

        return hardwareDevice(deviceID: deviceID)
    }

    nonisolated private static func defaultDeviceID(selector: AudioObjectPropertySelector) -> AudioDeviceID? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: selector,
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
            AppLogger.warning("Failed to read default audio device. status=\(status), deviceID=\(deviceID)")
            return nil
        }

        return deviceID
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
            transportType: deviceTransportType(deviceID: deviceID) ?? kAudioDeviceTransportTypeUnknown
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

    // MARK: - Device Enumeration

    /// Get all available audio input devices
    /// - Returns: Array of input devices, or empty array on failure
    nonisolated static func allInputDevices() -> [AudioHardwareDevice] {
        // Query CoreAudio for all audio devices
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )
        guard status == noErr else {
            AppLogger.warning("Failed to get audio devices data size. status=\(status)")
            return []
        }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceIDs
        )
        guard status == noErr else {
            AppLogger.warning("Failed to get audio devices. status=\(status)")
            return []
        }

        // Filter devices to only include those with input channels
        return deviceIDs.compactMap { deviceID in
            guard hasInputChannels(deviceID: deviceID),
                  let device = hardwareDevice(deviceID: deviceID) else {
                return nil
            }
            return device
        }
    }

//    Unused device lookup helpers kept commented for now while cleaning up older
//    audio-device-selection iterations.
//    /// Get device by AudioDeviceID
//    /// - Parameter deviceID: The device ID
//    /// - Returns: AudioHardwareDevice if device exists and has input channels, nil otherwise
//    nonisolated static func inputDevice(id deviceID: AudioDeviceID) -> AudioHardwareDevice? {
//        guard hasInputChannels(deviceID: deviceID),
//              let device = hardwareDevice(deviceID: deviceID) else {
//            return nil
//        }
//        return device
//    }
//
//    /// Get device by UID string
//    /// - Parameter uid: The device UID (persistent identifier)
//    /// - Returns: AudioHardwareDevice if device exists and has input channels, nil otherwise
//    nonisolated static func inputDevice(uid: String) -> AudioHardwareDevice? {
//        // Query CoreAudio to find device by UID
//        var propertyAddress = AudioObjectPropertyAddress(
//            mSelector: kAudioHardwarePropertyDevices,
//            mScope: kAudioObjectPropertyScopeGlobal,
//            mElement: kAudioObjectPropertyElementMain
//        )
//
//        var dataSize: UInt32 = 0
//        var status = AudioObjectGetPropertyDataSize(
//            AudioObjectID(kAudioObjectSystemObject),
//            &propertyAddress,
//            0,
//            nil,
//            &dataSize
//        )
//        guard status == noErr else {
//            return nil
//        }
//
//        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
//        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
//
//        status = AudioObjectGetPropertyData(
//            AudioObjectID(kAudioObjectSystemObject),
//            &propertyAddress,
//            0,
//            nil,
//            &dataSize,
//            &deviceIDs
//        )
//        guard status == noErr else {
//            return nil
//        }
//
//        // Find device with matching UID
//        for deviceID in deviceIDs {
//            guard let deviceUID = deviceUID(deviceID: deviceID),
//                  deviceUID == uid,
//                  hasInputChannels(deviceID: deviceID),
//                  let device = hardwareDevice(deviceID: deviceID) else {
//                continue
//            }
//            return device
//        }
//
//        return nil
//    }

    /// Check if device has input channels
    /// - Parameter deviceID: The device ID
    /// - Returns: true if device has at least one input channel, false otherwise or on error
    nonisolated static func hasInputChannels(deviceID: AudioDeviceID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize
        )
        guard status == noErr else {
            return false
        }

        let bufferListPointer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(dataSize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { bufferListPointer.deallocate() }

        let getStatus = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            bufferListPointer
        )
        guard getStatus == noErr else {
            return false
        }

        let bufferList = UnsafeMutableAudioBufferListPointer(
            bufferListPointer.assumingMemoryBound(to: AudioBufferList.self)
        )
        return bufferList.contains(where: { $0.mNumberChannels > 0 })
    }
}
#endif
