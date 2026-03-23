#if os(macOS)
import Combine
import Foundation

@MainActor
protocol MacGeneralSettingsAppModeling: AnyObject {
    func setLaunchAtLoginEnabled(_ enabled: Bool) throws
    func refreshRuntimeFromSettings()
    func applyDockVisibility(showInDock: Bool)
}

@MainActor
final class MacGeneralSettingsViewModel: ObservableObject {
    struct ManagedSettingsState {
        var launchAtLogin = false
        var showInDock = false
    }

    struct UpdateSettingsState {
        var isConfigured = false
        var canCheckForUpdates = false
        var isCheckingForUpdates = false
        var automaticallyChecksForUpdates = false
    }

    struct Feedback {
        let message: String
        let isError: Bool
    }

    struct Dependencies {
        var launchAtLoginIsEnabled: @MainActor () -> Bool = {
            MacAppBehaviorController.launchAtLoginIsEnabled()
        }
    }

    @Published var pauseMediaDuringDictation = false {
        didSet {
            guard hasLoadedPreferences else { return }
            defaults.set(pauseMediaDuringDictation, forKey: MacPreferences.pauseMediaDuringDictation)
        }
    }
    @Published var interactionSoundsEnabled = true {
        didSet {
            guard hasLoadedPreferences else { return }
            defaults.set(interactionSoundsEnabled, forKey: MacPreferences.interactionSoundsEnabled)
        }
    }
    @Published var shaderTheme = MacDictationVisualTheme.defaultTheme {
        didSet {
            guard hasLoadedPreferences else { return }
            defaults.set(shaderTheme.rawValue, forKey: MacPreferences.shaderTheme)
        }
    }
    @Published var managedSettings = ManagedSettingsState() {
        didSet {
            guard hasLoadedManagedSettings else { return }
            handleManagedSettingsMutation(oldValue: oldValue, newValue: managedSettings)
        }
    }
    @Published private(set) var updateSettings = UpdateSettingsState()
    @Published private(set) var feedback: Feedback?

    private let defaults: UserDefaults
    private let dependencies: Dependencies
    private var cancellables = Set<AnyCancellable>()

    private weak var appModel: (any MacGeneralSettingsAppModeling)?
    private weak var appUpdateManager: AppUpdateManager?

    private var hasLoadedPreferences = false
    private var hasLoadedManagedSettings = false
    private var suppressLaunchAtLoginChange = false
    private var suppressShowInDockChange = false

    init(
        defaults: UserDefaults = .standard,
        dependencies: Dependencies? = nil
    ) {
        self.defaults = defaults
        self.dependencies = dependencies ?? Dependencies()
    }

    func configure(
        appModel: any MacGeneralSettingsAppModeling,
        appUpdateManager: AppUpdateManager
    ) {
        self.appModel = appModel
        self.appUpdateManager = appUpdateManager

        cancellables.removeAll()
        appUpdateManager.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.syncUpdateSettingsFromManager()
            }
            .store(in: &cancellables)

        syncUpdateSettingsFromManager()
    }

    func load() {
        hasLoadedPreferences = false
        pauseMediaDuringDictation = defaults.object(forKey: MacPreferences.pauseMediaDuringDictation) as? Bool ?? false
        interactionSoundsEnabled = defaults.object(forKey: MacPreferences.interactionSoundsEnabled) as? Bool ?? true
        shaderTheme = loadShaderTheme()
        hasLoadedPreferences = true

        hasLoadedManagedSettings = false
        managedSettings = currentState()
        hasLoadedManagedSettings = true

        syncUpdateSettingsFromManager()
    }

    func loadState() -> ManagedSettingsState {
        currentState()
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        appUpdateManager?.setAutomaticallyChecksForUpdates(enabled)
        syncUpdateSettingsFromManager()
    }

    func checkForUpdates() {
        appUpdateManager?.checkForUpdates()
        syncUpdateSettingsFromManager()
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

    private func loadShaderTheme() -> MacDictationVisualTheme {
        MacDictationVisualTheme.fromStoredValue(
            defaults.string(forKey: MacPreferences.shaderTheme)
        )
    }

    func previewSound() {
        InteractionSoundPlayer().playPreview(preset: .defaultPreset)
    }

    private func handleManagedSettingsMutation(
        oldValue: ManagedSettingsState,
        newValue: ManagedSettingsState
    ) {
        if oldValue.launchAtLogin != newValue.launchAtLogin {
            handleLaunchAtLoginChange(oldValue: oldValue.launchAtLogin, newValue: newValue.launchAtLogin)
        }

        if oldValue.showInDock != newValue.showInDock {
            handleShowInDockChange(newValue.showInDock)
        }
    }

    private func handleLaunchAtLoginChange(oldValue: Bool, newValue: Bool) {
        if suppressLaunchAtLoginChange {
            suppressLaunchAtLoginChange = false
            return
        }

        guard let appModel else { return }

        let resolvedValue = applyLaunchAtLoginChange(
            oldValue: oldValue,
            newValue: newValue,
            appModel: appModel
        )

        if resolvedValue != newValue {
            suppressLaunchAtLoginChange = true
            managedSettings.launchAtLogin = resolvedValue
        }
    }

    private func handleShowInDockChange(_ newValue: Bool) {
        if suppressShowInDockChange {
            suppressShowInDockChange = false
            return
        }

        guard let appModel else { return }
        applyDockVisibilityChange(newValue, appModel: appModel)
    }

    private func syncUpdateSettingsFromManager() {
        guard let appUpdateManager else {
            updateSettings = UpdateSettingsState()
            return
        }

        updateSettings = UpdateSettingsState(
            isConfigured: appUpdateManager.isConfigured,
            canCheckForUpdates: appUpdateManager.canCheckForUpdates,
            isCheckingForUpdates: appUpdateManager.isChecking,
            automaticallyChecksForUpdates: appUpdateManager.automaticallyChecksForUpdates
        )
    }

    private func setFeedback(_ message: String, isError: Bool = false) {
        feedback = Feedback(message: message, isError: isError)
    }
}
#endif
