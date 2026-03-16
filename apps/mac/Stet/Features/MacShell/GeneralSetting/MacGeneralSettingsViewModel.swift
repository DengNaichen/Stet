#if os(macOS)
import Combine
import Foundation

@MainActor
final class MacGeneralSettingsViewModel: ObservableObject {
    struct ManagedSettingsState {
        var launchAtLogin = false
        var showInDock = false
        var selectedAudioInputDeviceID = 0
    }

    struct Feedback {
        let message: String
        let isError: Bool
    }

    @Published private(set) var feedback: Feedback?
    @Published private(set) var inputDevices: [AudioInputDevice] = []

    private let settingsStore: DictationSettingsStore
    private let defaults: UserDefaults

    init(
        settingsStore: DictationSettingsStore = DictationSettingsStore(),
        defaults: UserDefaults = .standard
    ) {
        self.settingsStore = settingsStore
        self.defaults = defaults
    }

    var systemDefaultInputDeviceLabel: String {
        if let defaultDeviceID = AudioInputDeviceManager.defaultInputDeviceID(),
           let device = inputDevices.first(where: { $0.id == defaultDeviceID }) {
            return "System Default (\(device.name))"
        }

        return "System Default"
    }

    func loadState() -> ManagedSettingsState {
        currentState()
    }

    @discardableResult
    func refreshInputDevices(selectedAudioInputDeviceID: Int) -> Int {
        inputDevices = AudioInputDeviceManager.availableInputDevices()

        guard !inputDevices.isEmpty else {
            return 0
        }

        let selectionExists = selectedAudioInputDeviceID == 0 ||
            inputDevices.contains(where: { Int($0.id) == selectedAudioInputDeviceID })
        let resolvedSelection = selectionExists ? selectedAudioInputDeviceID : 0
        defaults.set(resolvedSelection, forKey: MacPreferences.selectedAudioInputDeviceID)
        return resolvedSelection
    }

    func selectedAudioInputDeviceSummary(for selectedAudioInputDeviceID: Int) -> String? {
        if selectedAudioInputDeviceID == 0 {
            return AudioInputDeviceManager.defaultInputDeviceID()
                .flatMap { defaultDeviceID in
                    inputDevices.first(where: { $0.id == defaultDeviceID })?.name
                }
                .map { "Currently resolves to \($0)." }
        }

        if let selectedDevice = inputDevices.first(where: { Int($0.id) == selectedAudioInputDeviceID }) {
            return "Using \(selectedDevice.name) on the next capture."
        }

        return "The selected input device is unavailable. Refresh or switch back to System Default."
    }

    func exportConfiguration() {
        do {
            try MacConfigurationTransferManager.exportConfiguration(using: settingsStore)
            setFeedback("Configuration exported.")
        } catch {
            setFeedback(error.localizedDescription, isError: true)
        }
    }

    func importConfiguration(appModel: MacAppModel) -> ManagedSettingsState {
        do {
            try MacConfigurationTransferManager.importConfiguration(using: settingsStore)

            let importedLaunchAtLogin = defaults.object(forKey: MacPreferences.launchAtLogin) as? Bool
                ?? MacAppBehaviorController.launchAtLoginIsEnabled()

            do {
                try appModel.setLaunchAtLoginEnabled(importedLaunchAtLogin)
            } catch {
                let currentLaunchAtLoginPreference = MacAppBehaviorController.launchAtLoginIsEnabled()
                defaults.set(currentLaunchAtLoginPreference, forKey: MacPreferences.launchAtLogin)
                appModel.refreshRuntimeFromSettings()
                setFeedback(error.localizedDescription, isError: true)
                return currentState()
            }

            appModel.refreshRuntimeFromSettings()
            setFeedback("Configuration imported. API keys are still managed separately in Keychain.")
            return currentState()
        } catch {
            setFeedback(error.localizedDescription, isError: true)
            return currentState()
        }
    }

    func applyLaunchAtLoginChange(
        oldValue: Bool,
        newValue: Bool,
        appModel: MacAppModel
    ) -> Bool {
        do {
            try appModel.setLaunchAtLoginEnabled(newValue)
            defaults.set(newValue, forKey: MacPreferences.launchAtLogin)
            setFeedback(newValue ? "Launch at Login enabled." : "Launch at Login disabled.")
            return newValue
        } catch {
            defaults.set(oldValue, forKey: MacPreferences.launchAtLogin)
            setFeedback(error.localizedDescription, isError: true)
            return oldValue
        }
    }

    func applyDockVisibilityChange(_ showInDock: Bool, appModel: MacAppModel) {
        defaults.set(showInDock, forKey: MacPreferences.showInDock)
        appModel.applyDockVisibility(showInDock: showInDock)
        setFeedback(showInDock ? "Dock icon enabled." : "Dock icon hidden.")
    }

    func persistSelectedAudioInputDeviceID(_ selectedAudioInputDeviceID: Int) {
        defaults.set(selectedAudioInputDeviceID, forKey: MacPreferences.selectedAudioInputDeviceID)
    }

    private var currentShowInDockPreference: Bool {
        defaults.object(forKey: MacPreferences.showInDock) as? Bool ?? false
    }

    private func currentState() -> ManagedSettingsState {
        let currentLaunchAtLoginPreference = MacAppBehaviorController.launchAtLoginIsEnabled()
        defaults.set(currentLaunchAtLoginPreference, forKey: MacPreferences.launchAtLogin)

        return ManagedSettingsState(
            launchAtLogin: currentLaunchAtLoginPreference,
            showInDock: currentShowInDockPreference,
            selectedAudioInputDeviceID: refreshInputDevices(
                selectedAudioInputDeviceID: defaults.integer(forKey: MacPreferences.selectedAudioInputDeviceID)
            )
        )
    }

    private func setFeedback(_ message: String, isError: Bool = false) {
        feedback = Feedback(message: message, isError: isError)
    }
}
#endif
