#if os(macOS)
import Foundation

enum MacRecordingInputDeviceResolver {
    struct InputDeviceCandidate {
        let device: AudioHardwareDevice?
        let reason: Reason

        enum Reason: String {
            case selected
            case noExplicitDeviceFallback
            case builtInFallback
            case systemDefaultFallback
        }
    }

    nonisolated static func inputDeviceCandidates(
        defaults: UserDefaults = .standard
    ) -> [InputDeviceCandidate] {
        let selectedDevice = selectedRecordingDevice(defaults: defaults)
        let builtInDevice = AudioInputDeviceManager.builtInInputDevice()
        let defaultInputDevice = AudioInputDeviceManager.defaultInputDevice()

        var candidates: [InputDeviceCandidate] = []
        var seenUIDs = Set<String>()
        var hasSystemDefaultCandidate = false

        func append(_ device: AudioHardwareDevice?, reason: InputDeviceCandidate.Reason) {
            if let device {
                guard seenUIDs.insert(device.uid).inserted else {
                    return
                }
            } else {
                guard !hasSystemDefaultCandidate else {
                    return
                }
                hasSystemDefaultCandidate = true
            }

            candidates.append(InputDeviceCandidate(device: device, reason: reason))
        }

        if let selectedDevice {
            append(selectedDevice, reason: .selected)

            if defaultRouteMatches(device: selectedDevice, defaultInputDevice: defaultInputDevice) {
                append(nil, reason: .noExplicitDeviceFallback)
            }

            return candidates
        }

        append(nil, reason: .noExplicitDeviceFallback)
        append(builtInDevice, reason: .builtInFallback)
        append(defaultInputDevice, reason: .systemDefaultFallback)
        return candidates
    }

    nonisolated static func selectedRecordingDevice(
        defaults: UserDefaults = .standard
    ) -> AudioHardwareDevice? {
        let availableDevices = AudioInputDeviceManager.allInputDevices()
        let strategyRawValue = defaults.string(forKey: MacPreferences.audioDeviceSelectionStrategy) ?? ""
        let preferredUID = defaults.string(forKey: MacPreferences.preferredAudioInputDeviceUID)

        if strategyRawValue == AudioDeviceSelectionManager.SelectionStrategy.manual.rawValue {
            if let preferredUID,
               let preferredDevice = availableDevices.first(where: { $0.uid == preferredUID }) {
                return preferredDevice
            }

            return AudioInputDeviceManager.defaultInputDevice()
        }

        if let builtInDevice = availableDevices.first(where: \.isBuiltIn) {
            return builtInDevice
        }

        if let defaultInputDevice = AudioInputDeviceManager.defaultInputDevice(),
           let matchingDefaultDevice = availableDevices.first(where: { $0.uid == defaultInputDevice.uid }) {
            return matchingDefaultDevice
        }

        return availableDevices.max(by: { $0.automaticSelectionPriority < $1.automaticSelectionPriority })
    }

    nonisolated static func defaultRouteMatches(
        device: AudioHardwareDevice,
        defaultInputDevice: AudioHardwareDevice?
    ) -> Bool {
        guard let defaultInputDevice else {
            return false
        }

        return defaultInputDevice.uid == device.uid
    }

    nonisolated static func describe(candidate: InputDeviceCandidate) -> String {
        "\(candidate.reason.rawValue):\(candidate.device?.name ?? "systemDefault")"
    }
}
#endif
