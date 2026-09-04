#if os(macOS)
    import Foundation
    import StetCore

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
            .bool(MacPreferences.onboardingCompleted, false),
            .bool(MacPreferences.debugForceOnboarding, false),
            .bool(MacPreferences.pauseMediaDuringDictation, false),
            .bool(MacPreferences.mcpServerEnabled, false),
            .string(MacPreferences.transcriptionProvider, DictationProvider.openAI.rawValue),
            .string(MacPreferences.rewriteProvider, DictationProvider.openAI.rawValue),
            .bool(MacPreferences.rewriteEnabled, true),
            .bool(MacPreferences.interactionSoundsEnabled, true),
            .bool(MacPreferences.dictationCompletionNotificationsEnabled, true),
            .string(MacPreferences.interactionSoundPreset, InteractionSoundPreset.defaultPreset.rawValue),
            .string(MacPreferences.shaderTheme, MacDictationVisualTheme.egg.rawValue),
            .bool(MacPreferences.showInDock, false),
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
            defaults.set(
                InteractionSoundPreset.defaultPreset.rawValue,
                forKey: MacPreferences.interactionSoundPreset
            )

            //            if defaults.string(forKey: MacPreferences.dictationLanguageMode) == nil {
            //                settingsStore.saveDictationLanguageMode(.automatic)
            //            }

            if defaults.object(forKey: MacPreferences.hotkeyDistinguishModifierSides) == nil {
                settingsStore.saveHotkeyDistinguishModifierSides(false)
            }

            if defaults.object(forKey: MacPreferences.launchAtLogin) == nil {
                defaults.set(true, forKey: MacPreferences.launchAtLogin)
                Task { @MainActor in
                    try? MacAppBehaviorController.setLaunchAtLogin(true)
                }
            }
        }
    }
#endif
