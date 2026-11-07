#if os(macOS)
    import Combine
    import Foundation

    @MainActor
    final class AudioDeviceSelectionManager: ObservableObject {
        static let shared = AudioDeviceSelectionManager(provider: SystemAudioDeviceProvider())

        private let provider: AudioDeviceProviding
        private let defaults: UserDefaults
        private var preferredAudioInputDeviceUID: String?

        @Published private(set) var selectedDevice: AudioHardwareDevice?

        @Published private(set) var availableDevices: [AudioHardwareDevice] = []

        private(set) var preference: AudioDeviceSelectionResolver.Preference = .builtInDefault
        private(set) var activeDevice: AudioHardwareDevice?
        private(set) var isUsingFallbackBuiltIn = false

        init(
            provider: AudioDeviceProviding,
            defaults: UserDefaults = .standard
        ) {
            self.provider = provider
            self.defaults = defaults
            self.preferredAudioInputDeviceUID = defaults.string(forKey: MacPreferences.preferredAudioInputDeviceUID)
            refreshDevices()
        }

        func currentRecordingDevice() -> AudioHardwareDevice? {
            selectedDevice
        }

        func refreshDevices() {
            availableDevices = provider.allInputDevices()
            applyResolvedSelection()
        }

        func selectDevice(_ device: AudioHardwareDevice) {
            if device.isBuiltIn {
                selectBuiltInDefault()
                return
            }

            preferredAudioInputDeviceUID = device.uid
            persistPreferredDeviceUID()
            applyResolvedSelection()
        }

        func selectBuiltInDefault() {
            preferredAudioInputDeviceUID = nil
            persistPreferredDeviceUID()
            applyResolvedSelection()
        }

        private func persistPreferredDeviceUID() {
            if let uid = preferredAudioInputDeviceUID {
                defaults.set(uid, forKey: MacPreferences.preferredAudioInputDeviceUID)
            } else {
                defaults.removeObject(forKey: MacPreferences.preferredAudioInputDeviceUID)
            }
        }

        private func applyResolvedSelection() {
            let resolution = AudioDeviceSelectionResolver.resolve(
                availableDevices: availableDevices,
                defaultInputDevice: provider.defaultInputDevice(),
                preferredAudioInputDeviceUID: preferredAudioInputDeviceUID
            )
            preference = resolution.preference
            activeDevice = resolution.activeDevice
            isUsingFallbackBuiltIn = resolution.isUsingFallbackBuiltIn
            selectedDevice = resolution.activeDevice
        }
    }
#endif
