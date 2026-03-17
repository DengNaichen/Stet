#if os(macOS)
import Foundation
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
            launchAtLoginStatusProvider: { true },
            legacyHistoryURLs: []
        )

        let launchConfiguration = bootstrapper.prepareForLaunch()

        #expect(launchConfiguration == .init(showInDock: false))
        #expect(!defaults.bool(forKey: MacPreferences.pauseMediaDuringDictation))
        #expect(defaults.integer(forKey: MacPreferences.selectedAudioInputDeviceID) == 0)
        #expect(defaults.string(forKey: MacPreferences.transcriptionProvider) == DictationProvider.openAI.rawValue)
        #expect(defaults.string(forKey: MacPreferences.translationTargetLanguage) == TranslationTargetLanguage.english.rawValue)
        #expect(defaults.bool(forKey: MacPreferences.translateSelectedTextOnTranslationHotkey))
        #expect(defaults.string(forKey: MacPreferences.openAITranslationModel) == "gpt-5-mini")
        #expect(!defaults.bool(forKey: MacPreferences.hotkeyDistinguishModifierSides))
        #expect(defaults.bool(forKey: MacPreferences.interactionSoundsEnabled))
        #expect(defaults.string(forKey: MacPreferences.interactionSoundPreset) == InteractionSoundPreset.soft.rawValue)
        #expect(defaults.bool(forKey: MacPreferences.launchAtLogin))
        #expect(!defaults.bool(forKey: MacPreferences.showInDock))
        #expect(defaults.string(forKey: MacPreferences.proxyMode) == NetworkProxyMode.system.rawValue)
        #expect(defaults.string(forKey: MacPreferences.customProxyScheme) == CustomProxyScheme.http.rawValue)
    }

    @Test func prepareForLaunchRemovesLegacyArtifactsAndKeepsExplicitPreferences() throws {
        let defaults = TestSupport.makeUserDefaults()
        let settingsStore = DictationSettingsStore(defaults: defaults, secretStore: TestSecretStore())
        let legacyHistoryURL = TestSupport.temporaryFileURL("airtype-legacy-history", ext: "json")
        try Data("[]".utf8).write(to: legacyHistoryURL)

        defaults.set("legacy", forKey: "mac.copyLatestCaptureHotkeyShortcut")
        defaults.set("forever", forKey: "mac.historyRetentionPeriod")
        defaults.set(true, forKey: "mac.showPanelOnLaunch")
        defaults.set(true, forKey: "mac.copyToClipboardOnCapture")
        defaults.set(true, forKey: "mac.autoPasteOnCapture")
        defaults.set(true, forKey: "mac.revealPanelOnCapture")
        defaults.set(true, forKey: MacPreferences.showInDock)

        let bootstrapper = MacAppBootstrapper(
            defaults: defaults,
            settingsStore: settingsStore,
            launchAtLoginStatusProvider: { false },
            legacyHistoryURLs: [legacyHistoryURL]
        )

        let launchConfiguration = bootstrapper.prepareForLaunch()

        #expect(launchConfiguration == .init(showInDock: true))
        #expect(defaults.object(forKey: "mac.copyLatestCaptureHotkeyShortcut") == nil)
        #expect(defaults.object(forKey: "mac.historyRetentionPeriod") == nil)
        #expect(defaults.object(forKey: "mac.showPanelOnLaunch") == nil)
        #expect(defaults.object(forKey: "mac.copyToClipboardOnCapture") == nil)
        #expect(defaults.object(forKey: "mac.autoPasteOnCapture") == nil)
        #expect(defaults.object(forKey: "mac.revealPanelOnCapture") == nil)
        #expect(!FileManager.default.fileExists(atPath: legacyHistoryURL.path))
    }
}
#endif
