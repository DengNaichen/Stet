#if os(macOS)
import CoreAudio
import Foundation

struct AudioHardwareDevice: Equatable, Sendable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let transportType: UInt32
}

enum AudioInputDeviceManager {
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

    nonisolated static func defaultInputDevice() -> AudioHardwareDevice? {
        guard let deviceID = defaultInputDeviceID() else {
            return nil
        }

        return hardwareDevice(deviceID: deviceID)
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
}
#endif
