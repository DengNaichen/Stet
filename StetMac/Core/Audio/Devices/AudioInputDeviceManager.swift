#if os(macOS)
    import CoreAudio
    import Foundation
    import os

    enum AudioInputDeviceManager {
        nonisolated private static let logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "com.openwhispr.Stet",
            category: "AudioDevice"
        )

        nonisolated static func defaultInputDeviceID(system: AudioHardwareSystem = .shared) -> AudioDeviceID? {
            defaultDevice(system: system, input: true)?.id
        }

        nonisolated static func defaultOutputDeviceID(system: AudioHardwareSystem = .shared) -> AudioDeviceID? {
            defaultDevice(system: system, input: false)?.id
        }

        nonisolated static func defaultInputDevice(system: AudioHardwareSystem = .shared) -> AudioHardwareDevice? {
            defaultDevice(system: system, input: true).flatMap(hardwareDevice)
        }

        nonisolated static func builtInInputDevice() -> AudioHardwareDevice? {
            allInputDevices().first(where: \.isBuiltIn)
        }

        nonisolated static func defaultOutputDevice(system: AudioHardwareSystem = .shared) -> AudioHardwareDevice? {
            defaultDevice(system: system, input: false).flatMap(hardwareDevice)
        }

        nonisolated private static func defaultDevice(
            system: AudioHardwareSystem, input: Bool
        ) -> CoreAudio.AudioHardwareDevice? {
            do {
                let device = try input ? system.defaultInputDevice : system.defaultOutputDevice
                guard let device, device.id != kAudioObjectUnknown else {
                    logger.warning("No default audio device is available. input=\(input)")
                    return nil
                }
                return device
            } catch {
                logger.warning("Failed to read default audio device. input=\(input), error=\(error)")
                return nil
            }
        }

        nonisolated private static func hardwareDevice(_ device: CoreAudio.AudioHardwareDevice) -> AudioHardwareDevice?
        {
            guard let name = try? device.name, !name.isEmpty,
                let uid = try? device.uid
            else { return nil }

            return AudioHardwareDevice(
                id: device.id,
                uid: uid,
                name: name,
                transportType: (try? device.transportType) ?? kAudioDeviceTransportTypeUnknown
            )
        }

        /// A disappearing or unreadable device does not discard the other available inputs.
        nonisolated static func allInputDevices(system: AudioHardwareSystem = .shared) -> [AudioHardwareDevice] {
            do {
                return try system.devices.compactMap { device in
                    guard hasInputChannels(device) else { return nil }
                    return hardwareDevice(device)
                }
            } catch {
                logger.warning("Failed to get audio devices. error=\(error)")
                return []
            }
        }

        nonisolated static func hasInputChannels(deviceID: AudioDeviceID) -> Bool {
            hasInputChannels(CoreAudio.AudioHardwareDevice(id: deviceID))
        }

        nonisolated private static func hasInputChannels(_ device: CoreAudio.AudioHardwareDevice) -> Bool {
            (try? device.inputStreamConfiguration.contains { $0.mNumberChannels > 0 }) ?? false
        }
    }
#endif
