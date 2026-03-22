#if os(macOS)
@preconcurrency import AVFoundation
import Foundation

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

enum MacCaptureAudioDevicePlanner {
    nonisolated static func inputDeviceCandidates(
        selectedDevice: AudioHardwareDevice?
    ) -> [InputDeviceCandidate] {
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

            if Self.defaultRouteMatches(device: selectedDevice, defaultInputDevice: defaultInputDevice) {
                append(nil, reason: .noExplicitDeviceFallback)
            }

            return candidates
        }

        append(nil, reason: .noExplicitDeviceFallback)
        append(builtInDevice, reason: .builtInFallback)
        append(defaultInputDevice, reason: .systemDefaultFallback)
        return candidates
    }

    nonisolated static func resolveCaptureDevice(
        for device: AudioHardwareDevice?
    ) throws -> AVCaptureDevice {
        let availableDevices = availableCaptureDevices()

        guard let device else {
            if let defaultDevice = AVCaptureDevice.default(for: .audio) {
                return defaultDevice
            }

            if let fallbackDevice = availableDevices.first {
                return fallbackDevice
            }

            throw CaptureError.noCaptureDeviceAvailable
        }

        if let exactUIDMatch = availableDevices.first(where: { $0.uniqueID == device.uid }) {
            return exactUIDMatch
        }

        if let exactNameMatch = availableDevices.first(where: { $0.localizedName == device.name }) {
            return exactNameMatch
        }

        if device.isBuiltIn,
           let builtInLikeDevice = availableDevices.first(where: {
               $0.localizedName.localizedCaseInsensitiveContains("microphone")
                   || $0.localizedName.localizedCaseInsensitiveContains("macbook")
           }) {
            return builtInLikeDevice
        }

        throw CaptureError.selectedDeviceUnavailable(
            target: "\(device.name) (\(device.uid))",
            available: availableDevices.map { "\($0.localizedName) (\($0.uniqueID))" }
        )
    }

    nonisolated static func availableCaptureDevices() -> [AVCaptureDevice] {
        var devices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        ).devices

        if devices.isEmpty {
            devices = AVCaptureDevice.devices(for: .audio)
        }

        return devices
    }

    private nonisolated static func defaultRouteMatches(
        device: AudioHardwareDevice,
        defaultInputDevice: AudioHardwareDevice?
    ) -> Bool {
        guard let defaultInputDevice else {
            return false
        }

        return defaultInputDevice.uid == device.uid
    }
}
#endif
