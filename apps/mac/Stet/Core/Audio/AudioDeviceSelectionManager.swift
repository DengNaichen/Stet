#if os(macOS)
import Combine
import Foundation

@MainActor
final class AudioDeviceSelectionManager: ObservableObject {
    private nonisolated final class RecordingDeviceCache: @unchecked Sendable {
        private let lock = NSLock()
        private var device: AudioHardwareDevice?

        func load() -> AudioHardwareDevice? {
            lock.lock()
            defer { lock.unlock() }
            return device
        }

        func store(_ device: AudioHardwareDevice?) {
            lock.lock()
            self.device = device
            lock.unlock()
        }
    }

    static let shared = AudioDeviceSelectionManager(provider: SystemAudioDeviceProvider())

    private let provider: AudioDeviceProviding
    private let defaults: UserDefaults
    private let recordingDeviceCache = RecordingDeviceCache()
    private var preferredAudioInputDeviceUID: String?

    @Published private(set) var selectedDevice: AudioHardwareDevice? {
        didSet {
            updateRecordingDeviceCache(selectedDevice)
        }
    }

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

    nonisolated func currentRecordingDevice() -> AudioHardwareDevice? {
        recordingDeviceCache.load()
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

    private func updateRecordingDeviceCache(_ device: AudioHardwareDevice?) {
        recordingDeviceCache.store(device)
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
