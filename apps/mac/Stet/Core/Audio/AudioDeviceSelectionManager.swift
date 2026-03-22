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
    private let recordingDeviceCache = RecordingDeviceCache()

    @Published private(set) var selectedDevice: AudioHardwareDevice? {
        didSet {
            updateRecordingDeviceCache(selectedDevice)
        }
    }

    @Published private(set) var availableDevices: [AudioHardwareDevice] = []

    enum SelectionStrategy: String, Codable {
        case automatic
        case manual
    }

    @Published var strategy: SelectionStrategy = .automatic {
        didSet {
            persistStrategy()
            selectedDevice = deviceForRecording()
        }
    }

    @Published var preferredDeviceUID: String? {
        didSet {
            persistPreferredDeviceUID()
            selectedDevice = deviceForRecording()
        }
    }

    init(provider: AudioDeviceProviding) {
        self.provider = provider

        if let savedStrategyRaw = UserDefaults.standard.string(forKey: MacPreferences.audioDeviceSelectionStrategy),
           let savedStrategy = SelectionStrategy(rawValue: savedStrategyRaw) {
            self.strategy = savedStrategy
        }

        self.preferredDeviceUID = UserDefaults.standard.string(forKey: MacPreferences.preferredAudioInputDeviceUID)
        refreshDevices()
    }

    nonisolated func currentRecordingDevice() -> AudioHardwareDevice? {
        recordingDeviceCache.load()
    }

    func refreshDevices() {
        availableDevices = provider.allInputDevices()
        selectedDevice = deviceForRecording()
    }

    func selectDevice(_ device: AudioHardwareDevice) {
        strategy = .manual
        preferredDeviceUID = device.uid
    }

    func resetToAutomatic() {
        strategy = .automatic
        preferredDeviceUID = nil
    }

    func deviceForRecording() -> AudioHardwareDevice? {
        switch strategy {
        case .automatic:
            return selectDefaultDevice(from: availableDevices)
        case .manual:
            if let uid = preferredDeviceUID,
               let device = availableDevices.first(where: { $0.uid == uid }) {
                return device
            }

            return provider.defaultInputDevice()
        }
    }

    private func selectDefaultDevice(from devices: [AudioHardwareDevice]) -> AudioHardwareDevice? {
        if let builtInDevice = devices.first(where: \.isBuiltIn) {
            return builtInDevice
        }

        if let defaultInputDevice = provider.defaultInputDevice(),
           let matchingDefaultDevice = devices.first(where: { $0.uid == defaultInputDevice.uid }) {
            return matchingDefaultDevice
        }

        return devices.max(by: { $0.automaticSelectionPriority < $1.automaticSelectionPriority })
    }

    private func persistStrategy() {
        UserDefaults.standard.set(strategy.rawValue, forKey: MacPreferences.audioDeviceSelectionStrategy)
    }

    private func persistPreferredDeviceUID() {
        if let uid = preferredDeviceUID {
            UserDefaults.standard.set(uid, forKey: MacPreferences.preferredAudioInputDeviceUID)
        } else {
            UserDefaults.standard.removeObject(forKey: MacPreferences.preferredAudioInputDeviceUID)
        }
    }

    private func updateRecordingDeviceCache(_ device: AudioHardwareDevice?) {
        recordingDeviceCache.store(device)
    }
}
#endif
