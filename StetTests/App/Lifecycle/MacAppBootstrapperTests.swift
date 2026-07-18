#if os(macOS)
    import Foundation
    import StetCore
    import Testing

    @testable import Stet

    @MainActor
    @Suite("Mac App Bootstrapper", .serialized)
    struct MacAppBootstrapperTests {
        @Test func prepareForLaunchAppliesMissingDefaults() {
            let defaults = TestSupport.makeUserDefaults()
            let settingsStore = DictationSettingsStore(defaults: defaults, secretStore: TestSecretStore())
            let bootstrapper = MacAppBootstrapper(
                defaults: defaults,
                settingsStore: settingsStore,
                launchAtLoginStatusProvider: { true }
            )

            let launchConfiguration = bootstrapper.prepareForLaunch()

            #expect(launchConfiguration == .init(showInDock: false))
            #expect(!defaults.bool(forKey: MacPreferences.pauseMediaDuringDictation))
            #expect(!defaults.bool(forKey: MacPreferences.mcpServerEnabled))
            #expect(defaults.string(forKey: MacPreferences.transcriptionProvider) == DictationProvider.openAI.rawValue)
            #expect(defaults.string(forKey: MacPreferences.rewriteProvider) == DictationProvider.openAI.rawValue)
            #expect(defaults.string(forKey: MacPreferences.transcriptionPrimaryLanguage) == "en")
            #expect(!defaults.bool(forKey: MacPreferences.hotkeyDistinguishModifierSides))
            #expect(defaults.bool(forKey: MacPreferences.interactionSoundsEnabled))
            #expect(
                defaults.string(forKey: MacPreferences.interactionSoundPreset) == InteractionSoundPreset.soft.rawValue)
            #expect(
                defaults.string(forKey: MacPreferences.shaderTheme)
                    == MacDictationVisualTheme.egg.rawValue)
            #expect(defaults.bool(forKey: MacPreferences.launchAtLogin))
            #expect(!defaults.bool(forKey: MacPreferences.showInDock))
        }

        @Test func prepareForLaunchKeepsExplicitPreferencesAndAppliesMissingDefaults() throws {
            let defaults = TestSupport.makeUserDefaults()
            let settingsStore = DictationSettingsStore(defaults: defaults, secretStore: TestSecretStore())
            defaults.set("legacy", forKey: "mac.copyLatestCaptureHotkeyShortcut")
            defaults.set("forever", forKey: "mac.historyRetentionPeriod")
            defaults.set(true, forKey: "mac.showPanelOnLaunch")
            defaults.set(true, forKey: "mac.copyToClipboardOnCapture")
            defaults.set(true, forKey: "mac.autoPasteOnCapture")
            defaults.set(true, forKey: "mac.revealPanelOnCapture")
            defaults.set("https://api.groq.com/openai/v1", forKey: "mac.openAIBaseURL")
            defaults.set(true, forKey: MacPreferences.showInDock)

            let bootstrapper = MacAppBootstrapper(
                defaults: defaults,
                settingsStore: settingsStore,
                launchAtLoginStatusProvider: { false }
            )

            let launchConfiguration = bootstrapper.prepareForLaunch()

            #expect(launchConfiguration == .init(showInDock: true))
            #expect(defaults.object(forKey: "mac.copyLatestCaptureHotkeyShortcut") as? String == "legacy")
            #expect(defaults.object(forKey: "mac.historyRetentionPeriod") as? String == "forever")
            #expect(defaults.object(forKey: "mac.showPanelOnLaunch") as? Bool == true)
            #expect(defaults.object(forKey: "mac.copyToClipboardOnCapture") as? Bool == true)
            #expect(defaults.object(forKey: "mac.autoPasteOnCapture") as? Bool == true)
            #expect(defaults.object(forKey: "mac.revealPanelOnCapture") as? Bool == true)
            #expect(defaults.object(forKey: "mac.openAIBaseURL") as? String == "https://api.groq.com/openai/v1")
            #expect(defaults.string(forKey: MacPreferences.transcriptionPrimaryLanguage) == "en")
            #expect(defaults.object(forKey: MacPreferences.hotkeyDistinguishModifierSides) as? Bool == false)
            #expect(defaults.bool(forKey: MacPreferences.launchAtLogin))
        }

        @Test func prepareForLaunchResetsLegacyInteractionSoundPresetToDefault() {
            let defaults = TestSupport.makeUserDefaults()
            let settingsStore = DictationSettingsStore(defaults: defaults, secretStore: TestSecretStore())
            defaults.set(InteractionSoundPreset.glass.rawValue, forKey: MacPreferences.interactionSoundPreset)

            let bootstrapper = MacAppBootstrapper(
                defaults: defaults,
                settingsStore: settingsStore,
                launchAtLoginStatusProvider: { false }
            )

            _ = bootstrapper.prepareForLaunch()

            #expect(
                defaults.string(forKey: MacPreferences.interactionSoundPreset)
                    == InteractionSoundPreset.defaultPreset.rawValue
            )
        }
    }
#endif
