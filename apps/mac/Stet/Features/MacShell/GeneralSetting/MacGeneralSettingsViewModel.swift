#if os(macOS)
import Combine
import Foundation

@MainActor
protocol MacGeneralSettingsAppModeling {
    func setLaunchAtLoginEnabled(_ enabled: Bool) throws
    func refreshRuntimeFromSettings()
    func applyDockVisibility(showInDock: Bool)
}

extension MacAppModel: MacGeneralSettingsAppModeling {}

@MainActor
final class MacGeneralSettingsViewModel: ObservableObject {
    struct ManagedSettingsState {
        var launchAtLogin = false
        var showInDock = false
    }

    struct Feedback {
        let message: String
        let isError: Bool
    }

    struct Dependencies {
        var launchAtLoginIsEnabled: @MainActor () -> Bool = {
            MacAppBehaviorController.launchAtLoginIsEnabled()
        }
        var exportConfiguration: @MainActor (DictationSettingsStore) throws -> Void = {
            try MacConfigurationTransferManager.exportConfiguration(using: $0)
        }
        var importConfiguration: @MainActor (DictationSettingsStore) throws -> Void = {
            try MacConfigurationTransferManager.importConfiguration(using: $0)
        }
    }

    @Published private(set) var feedback: Feedback?

    private let settingsStore: DictationSettingsStore
    private let defaults: UserDefaults
    private let dependencies: Dependencies

    init(
        settingsStore: DictationSettingsStore = DictationSettingsStore(),
        defaults: UserDefaults = .standard,
        dependencies: Dependencies = Dependencies()
    ) {
        self.settingsStore = settingsStore
        self.defaults = defaults
        self.dependencies = dependencies
    }

    func loadState() -> ManagedSettingsState {
        currentState()
    }

    func exportConfiguration() {
        do {
            try dependencies.exportConfiguration(settingsStore)
            setFeedback("Configuration exported.")
        } catch {
            setFeedback(error.localizedDescription, isError: true)
        }
    }

    func importConfiguration(appModel: any MacGeneralSettingsAppModeling) -> ManagedSettingsState {
        do {
            try dependencies.importConfiguration(settingsStore)

            let importedLaunchAtLogin = defaults.object(forKey: MacPreferences.launchAtLogin) as? Bool
                ?? dependencies.launchAtLoginIsEnabled()

            do {
                try appModel.setLaunchAtLoginEnabled(importedLaunchAtLogin)
            } catch {
                let currentLaunchAtLoginPreference = dependencies.launchAtLoginIsEnabled()
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
        appModel: any MacGeneralSettingsAppModeling
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

    func applyDockVisibilityChange(_ showInDock: Bool, appModel: any MacGeneralSettingsAppModeling) {
        defaults.set(showInDock, forKey: MacPreferences.showInDock)
        appModel.applyDockVisibility(showInDock: showInDock)
        setFeedback(showInDock ? "Dock icon enabled." : "Dock icon hidden.")
    }

    private var currentShowInDockPreference: Bool {
        defaults.object(forKey: MacPreferences.showInDock) as? Bool ?? false
    }

    private func currentState() -> ManagedSettingsState {
        let currentLaunchAtLoginPreference = dependencies.launchAtLoginIsEnabled()
        defaults.set(currentLaunchAtLoginPreference, forKey: MacPreferences.launchAtLogin)

        return ManagedSettingsState(
            launchAtLogin: currentLaunchAtLoginPreference,
            showInDock: currentShowInDockPreference
        )
    }

    private func setFeedback(_ message: String, isError: Bool = false) {
        feedback = Feedback(message: message, isError: isError)
    }
}
#endif
