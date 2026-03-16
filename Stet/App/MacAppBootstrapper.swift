#if os(macOS)
import Foundation

struct MacAppBootstrapper {
    private enum LegacyPreferenceKey {
        static let copyLatestCaptureHotkeyShortcut = "mac.copyLatestCaptureHotkeyShortcut"
        static let historyRetentionPeriod = "mac.historyRetentionPeriod"
    }

    struct LaunchConfiguration: Equatable {
        let showInDock: Bool
        let shouldShowPanelOnLaunch: Bool
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
        .bool(MacPreferences.showPanelOnLaunch, false),
        .bool(MacPreferences.copyToClipboardOnCapture, true),
        .bool(MacPreferences.autoPasteOnCapture, true),
        .bool(MacPreferences.revealPanelOnCapture, false),
        .bool(MacPreferences.pauseMediaDuringDictation, false),
        .integer(MacPreferences.selectedAudioInputDeviceID, 0),
        .string(MacPreferences.transcriptionProvider, DictationProvider.openAI.rawValue),
        .bool(MacPreferences.rewriteEnabled, false),
        .string(MacPreferences.openAITranslationModel, "gpt-5-mini"),
        .bool(MacPreferences.interactionSoundsEnabled, true),
        .string(MacPreferences.interactionSoundPreset, InteractionSoundPreset.soft.rawValue),
        .bool(MacPreferences.showInDock, false),
        .string(MacPreferences.proxyMode, NetworkProxyMode.system.rawValue),
        .string(MacPreferences.customProxyScheme, CustomProxyScheme.http.rawValue),
        .bool(MacPreferences.hotkeyDebugLoggingEnabled, false),
        .bool(MacPreferences.openAIDebugLoggingEnabled, false),
    ]

    private let defaults: UserDefaults
    private let settingsStore: DictationSettingsStore
    private let fileManager: FileManager
    private let launchAtLoginStatusProvider: () -> Bool
    private let legacyHistoryURLs: [URL]

    init(
        defaults: UserDefaults = .standard,
        settingsStore: DictationSettingsStore,
        fileManager: FileManager = .default,
        launchAtLoginStatusProvider: @escaping () -> Bool = { MacAppBehaviorController.launchAtLoginIsEnabled() },
        legacyHistoryURLs: [URL]? = nil
    ) {
        self.defaults = defaults
        self.settingsStore = settingsStore
        self.fileManager = fileManager
        self.launchAtLoginStatusProvider = launchAtLoginStatusProvider
        self.legacyHistoryURLs = legacyHistoryURLs ?? Self.makeLegacyHistoryURLs(fileManager: fileManager)
    }

    func prepareForLaunch() -> LaunchConfiguration {
        removeLegacyArtifacts()
        applyDefaultPreferences()

        return LaunchConfiguration(
            showInDock: defaults.object(forKey: MacPreferences.showInDock) as? Bool ?? false,
            shouldShowPanelOnLaunch: defaults.bool(forKey: MacPreferences.showPanelOnLaunch)
        )
    }

    private func applyDefaultPreferences() {
        Self.defaultPreferences.forEach { $0.applyIfMissing(to: defaults) }

        if defaults.string(forKey: MacPreferences.translationTargetLanguage) == nil {
            settingsStore.saveTranslationTargetLanguage(.english)
        }

        if defaults.object(forKey: MacPreferences.translateSelectedTextOnTranslationHotkey) == nil {
            settingsStore.saveTranslateSelectedTextOnTranslationHotkey(true)
        }

        if defaults.object(forKey: MacPreferences.hotkeyDistinguishModifierSides) == nil {
            settingsStore.saveHotkeyDistinguishModifierSides(false)
        }

        if defaults.object(forKey: MacPreferences.launchAtLogin) == nil {
            defaults.set(launchAtLoginStatusProvider(), forKey: MacPreferences.launchAtLogin)
        }
    }

    private func removeLegacyArtifacts() {
        defaults.removeObject(forKey: LegacyPreferenceKey.copyLatestCaptureHotkeyShortcut)
        defaults.removeObject(forKey: LegacyPreferenceKey.historyRetentionPeriod)

        for url in legacyHistoryURLs {
            try? fileManager.removeItem(at: url)
        }
    }

    private static func makeLegacyHistoryURLs(fileManager: FileManager) -> [URL] {
        var urls: [URL] = [
            fileManager.temporaryDirectory.appendingPathComponent("Stet-transcription-history.json")
        ]

        if let applicationSupport = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) {
            urls.append(
                applicationSupport
                    .appendingPathComponent("Stet", isDirectory: true)
                    .appendingPathComponent("transcription-history.json")
            )
        }

        return urls
    }
}
#endif
