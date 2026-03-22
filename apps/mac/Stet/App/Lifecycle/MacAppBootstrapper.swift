#if os(macOS)
import Foundation
import StetVisuals

struct MacAppBootstrapper {
    struct LaunchConfiguration: Equatable {
        let showInDock: Bool
    }

    private enum DefaultPreference {
        case bool(String, Bool)
        case integer(String, Int)
        case string(String, String)

        func applyIfMissing(to defaults: UserDefaults) {
            switch self {
            case .bool(let key, let value):
                guard defaults.object(forKey: key) == nil else { return }
                defaults.set(value, forKey: key)
            case .integer(let key, let value):
                guard defaults.object(forKey: key) == nil else { return }
                defaults.set(value, forKey: key)
            case .string(let key, let value):
                guard defaults.string(forKey: key) == nil else { return }
                defaults.set(value, forKey: key)
            }
        }
    }

    private static let defaultPreferences: [DefaultPreference] = [
        .bool(MacPreferences.onboardingCompleted, true),
        .bool(MacPreferences.pauseMediaDuringDictation, false),
        .string(MacPreferences.transcriptionProvider, DictationProvider.openAI.rawValue),
        .string(MacPreferences.aiExecutionMode, AIExecutionMode.automatic.rawValue),
        .bool(MacPreferences.rewriteEnabled, false),
        .bool(MacPreferences.interactionSoundsEnabled, true),
        .string(MacPreferences.interactionSoundPreset, InteractionSoundPreset.soft.rawValue),
        .string(MacPreferences.shaderTheme, MacDictationShaderTheme.defaultTheme.rawValue),
        .bool(MacPreferences.showInDock, false),
        .bool(MacPreferences.hotkeyDebugLoggingEnabled, false),
        .bool(MacPreferences.openAIDebugLoggingEnabled, false),
    ]

    private let defaults: UserDefaults
    private let settingsStore: DictationSettingsStore
    private let launchAtLoginStatusProvider: () -> Bool

    init(
        defaults: UserDefaults = .standard,
        settingsStore: DictationSettingsStore,
        launchAtLoginStatusProvider: @escaping () -> Bool = { MacAppBehaviorController.launchAtLoginIsEnabled() }
    ) {
        self.defaults = defaults
        self.settingsStore = settingsStore
        self.launchAtLoginStatusProvider = launchAtLoginStatusProvider
    }

    func prepareForLaunch() -> LaunchConfiguration {
        applyDefaultPreferences()

        return LaunchConfiguration(
            showInDock: defaults.object(forKey: MacPreferences.showInDock) as? Bool ?? false
        )
    }

    private func applyDefaultPreferences() {
        Self.defaultPreferences.forEach { $0.applyIfMissing(to: defaults) }

        if defaults.string(forKey: MacPreferences.dictationLanguageMode) == nil {
            settingsStore.saveDictationLanguageMode(.automatic)
        }

        if defaults.object(forKey: MacPreferences.hotkeyDistinguishModifierSides) == nil {
            settingsStore.saveHotkeyDistinguishModifierSides(false)
        }

        if defaults.object(forKey: MacPreferences.launchAtLogin) == nil {
            defaults.set(launchAtLoginStatusProvider(), forKey: MacPreferences.launchAtLogin)
        }
    }
}
#endif
