#if os(macOS)
import Combine
import Foundation

@MainActor
final class MacGeneralSettingsViewModel: ObservableObject {
    struct RestoredState {
        let launchAtLogin: Bool
        let selectedAudioInputDeviceID: Int
    }

    @Published private(set) var message: String?
    @Published private(set) var messageIsError = false
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

    func load(currentSelectedAudioInputDeviceID: Int) -> RestoredState {
        RestoredState(
            launchAtLogin: MacAppBehaviorController.launchAtLoginIsEnabled(),
            selectedAudioInputDeviceID: refreshInputDevices(
                selectedAudioInputDeviceID: currentSelectedAudioInputDeviceID
            )
        )
    }

    @discardableResult
    func refreshInputDevices(selectedAudioInputDeviceID: Int) -> Int {
        inputDevices = AudioInputDeviceManager.availableInputDevices()

        guard !inputDevices.isEmpty else {
            return 0
        }

        let selectionExists = selectedAudioInputDeviceID == 0 ||
            inputDevices.contains(where: { Int($0.id) == selectedAudioInputDeviceID })

        return selectionExists ? selectedAudioInputDeviceID : 0
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
            setMessage("Configuration exported.")
        } catch {
            setMessage(error.localizedDescription, isError: true)
        }
    }

    func importConfiguration(
        appModel: MacAppModel,
        currentSelectedAudioInputDeviceID: Int
    ) -> RestoredState {
        do {
            try MacConfigurationTransferManager.importConfiguration(using: settingsStore)

            let importedLaunchAtLogin = defaults.object(forKey: MacPreferences.launchAtLogin) as? Bool
                ?? MacAppBehaviorController.launchAtLoginIsEnabled()

            do {
                try appModel.setLaunchAtLoginEnabled(importedLaunchAtLogin)
            } catch {
                setMessage(error.localizedDescription, isError: true)
                return RestoredState(
                    launchAtLogin: MacAppBehaviorController.launchAtLoginIsEnabled(),
                    selectedAudioInputDeviceID: refreshInputDevices(
                        selectedAudioInputDeviceID: currentSelectedAudioInputDeviceID
                    )
                )
            }

            appModel.refreshRuntimeFromSettings()
            setMessage("Configuration imported. API keys are still managed separately in Keychain.")

            let restoredSelection = defaults.integer(forKey: MacPreferences.selectedAudioInputDeviceID)
            return RestoredState(
                launchAtLogin: importedLaunchAtLogin,
                selectedAudioInputDeviceID: refreshInputDevices(
                    selectedAudioInputDeviceID: restoredSelection
                )
            )
        } catch {
            setMessage(error.localizedDescription, isError: true)
            return RestoredState(
                launchAtLogin: MacAppBehaviorController.launchAtLoginIsEnabled(),
                selectedAudioInputDeviceID: refreshInputDevices(
                    selectedAudioInputDeviceID: currentSelectedAudioInputDeviceID
                )
            )
        }
    }

    func applyLaunchAtLoginChange(
        oldValue: Bool,
        newValue: Bool,
        appModel: MacAppModel
    ) -> Bool {
        do {
            try appModel.setLaunchAtLoginEnabled(newValue)
            setMessage(newValue ? "Launch at Login enabled." : "Launch at Login disabled.")
            return newValue
        } catch {
            setMessage(error.localizedDescription, isError: true)
            return oldValue
        }
    }

    func applyDockVisibilityChange(_ showInDock: Bool, appModel: MacAppModel) {
        appModel.applyDockVisibility(showInDock: showInDock)
        setMessage(showInDock ? "Dock icon enabled." : "Dock icon hidden.")
    }

    func previewInteractionSound(_ preset: InteractionSoundPreset, appModel: MacAppModel) {
        appModel.previewInteractionSound(preset)
    }

    private func setMessage(_ message: String, isError: Bool = false) {
        self.message = message
        messageIsError = isError
    }
}
#endif
