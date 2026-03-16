#if os(macOS)
import AppKit
import Foundation
import UniformTypeIdentifiers

enum MacConfigurationTransferError: LocalizedError, Equatable {
    case invalidData

    var errorDescription: String? {
        switch self {
        case .invalidData:
            return "The configuration file is invalid."
        }
    }
}

enum MacConfigurationTransferManager {
    private struct ExportedConfiguration: Codable {
        var version: Int
        var showPanelOnLaunch: Bool
        var copyToClipboardOnCapture: Bool
        var autoPasteOnCapture: Bool
        var revealPanelOnCapture: Bool
        var pauseMediaDuringDictation: Bool
        var selectedAudioInputDeviceID: Int
        var transcriptionProvider: String
        var rewriteEnabled: Bool
        var openAIBaseURL: String?
        var translationTargetLanguage: String
        var translateSelectedTextOnTranslationHotkey: Bool
        var openAITranslationModel: String
        var interactionSoundsEnabled: Bool
        var interactionSoundPreset: String
        var launchAtLogin: Bool
        var showInDock: Bool
        var hotkeyDistinguishModifierSides: Bool
        var personalDictionary: [String]
        var historyRetentionPeriod: String
        var proxyMode: String
        var customProxyScheme: String
        var customProxyHost: String
        var customProxyPort: String
        var hotkeyDebugLoggingEnabled: Bool
        var openAIDebugLoggingEnabled: Bool
        var openAIAPIKeyPlaceholder: String
    }

    static func exportConfiguration(using store: DictationSettingsStore = DictationSettingsStore()) throws {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.json]
        savePanel.canCreateDirectories = true
        savePanel.nameFieldStringValue = "airtype-config.json"

        guard savePanel.runModal() == .OK, let url = savePanel.url else { return }

        let data = try exportData(using: store)
        try data.write(to: url, options: .atomic)
    }

    static func importConfiguration(using store: DictationSettingsStore = DictationSettingsStore()) throws {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        let data = try Data(contentsOf: url)
        try importData(data, using: store)
    }

    static func exportData(
        using store: DictationSettingsStore = DictationSettingsStore(),
        defaults: UserDefaults = .standard
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(makeExportedConfiguration(using: store, defaults: defaults))
    }

    static func importData(
        _ data: Data,
        using store: DictationSettingsStore = DictationSettingsStore(),
        defaults: UserDefaults = .standard
    ) throws {
        let decoder = JSONDecoder()

        guard let imported = try? decoder.decode(ExportedConfiguration.self, from: data) else {
            throw MacConfigurationTransferError.invalidData
        }

        apply(imported, using: store, defaults: defaults)
    }

    private static func makeExportedConfiguration(
        using store: DictationSettingsStore,
        defaults: UserDefaults
    ) -> ExportedConfiguration {
        let proxySettings = store.loadProxySettings()

        return ExportedConfiguration(
            version: 1,
            showPanelOnLaunch: defaults.bool(forKey: MacPreferences.showPanelOnLaunch),
            copyToClipboardOnCapture: defaults.bool(forKey: MacPreferences.copyToClipboardOnCapture),
            autoPasteOnCapture: defaults.bool(forKey: MacPreferences.autoPasteOnCapture),
            revealPanelOnCapture: defaults.bool(forKey: MacPreferences.revealPanelOnCapture),
            pauseMediaDuringDictation: defaults.bool(forKey: MacPreferences.pauseMediaDuringDictation),
            selectedAudioInputDeviceID: defaults.integer(forKey: MacPreferences.selectedAudioInputDeviceID),
            transcriptionProvider: DictationProvider(
                rawValue: defaults.string(forKey: MacPreferences.transcriptionProvider) ?? ""
            )?.rawValue ?? DictationProvider.openAI.rawValue,
            rewriteEnabled: defaults.bool(forKey: MacPreferences.rewriteEnabled),
            openAIBaseURL: store.loadOpenAIBaseURL().absoluteString,
            translationTargetLanguage: store.loadTranslationTargetLanguage().rawValue,
            translateSelectedTextOnTranslationHotkey: store.loadTranslateSelectedTextOnTranslationHotkey(),
            openAITranslationModel: store.loadOpenAITranslationModel(),
            interactionSoundsEnabled: defaults.object(forKey: MacPreferences.interactionSoundsEnabled) as? Bool ?? true,
            interactionSoundPreset: defaults.string(forKey: MacPreferences.interactionSoundPreset) ?? InteractionSoundPreset.soft.rawValue,
            launchAtLogin: defaults.object(forKey: MacPreferences.launchAtLogin) as? Bool ?? false,
            showInDock: defaults.object(forKey: MacPreferences.showInDock) as? Bool ?? false,
            hotkeyDistinguishModifierSides: store.loadHotkeyDistinguishModifierSides(),
            personalDictionary: store.loadPersonalDictionary(),
            historyRetentionPeriod: store.loadHistoryRetentionPeriod().rawValue,
            proxyMode: proxySettings.mode.rawValue,
            customProxyScheme: proxySettings.customScheme.rawValue,
            customProxyHost: proxySettings.customHost,
            customProxyPort: proxySettings.customPort.map(String.init) ?? "",
            hotkeyDebugLoggingEnabled: defaults.object(forKey: MacPreferences.hotkeyDebugLoggingEnabled) as? Bool ?? false,
            openAIDebugLoggingEnabled: defaults.object(forKey: MacPreferences.openAIDebugLoggingEnabled) as? Bool ?? false,
            openAIAPIKeyPlaceholder: store.loadOpenAIAPIKey().isEmpty ? "" : "set-manually"
        )
    }

    private static func apply(
        _ imported: ExportedConfiguration,
        using store: DictationSettingsStore,
        defaults: UserDefaults
    ) {
        defaults.set(imported.showPanelOnLaunch, forKey: MacPreferences.showPanelOnLaunch)
        defaults.set(imported.copyToClipboardOnCapture, forKey: MacPreferences.copyToClipboardOnCapture)
        defaults.set(imported.autoPasteOnCapture, forKey: MacPreferences.autoPasteOnCapture)
        defaults.set(imported.revealPanelOnCapture, forKey: MacPreferences.revealPanelOnCapture)
        defaults.set(imported.pauseMediaDuringDictation, forKey: MacPreferences.pauseMediaDuringDictation)
        defaults.set(imported.selectedAudioInputDeviceID, forKey: MacPreferences.selectedAudioInputDeviceID)
        defaults.set(
            DictationProvider(rawValue: imported.transcriptionProvider)?.rawValue ?? DictationProvider.openAI.rawValue,
            forKey: MacPreferences.transcriptionProvider
        )
        defaults.set(imported.rewriteEnabled, forKey: MacPreferences.rewriteEnabled)
        defaults.set(imported.openAIBaseURL ?? "https://api.openai.com/v1", forKey: MacPreferences.openAIBaseURL)
        defaults.set(imported.translationTargetLanguage, forKey: MacPreferences.translationTargetLanguage)
        defaults.set(
            imported.translateSelectedTextOnTranslationHotkey,
            forKey: MacPreferences.translateSelectedTextOnTranslationHotkey
        )
        defaults.set(imported.openAITranslationModel, forKey: MacPreferences.openAITranslationModel)
        defaults.set(imported.interactionSoundsEnabled, forKey: MacPreferences.interactionSoundsEnabled)
        defaults.set(imported.interactionSoundPreset, forKey: MacPreferences.interactionSoundPreset)
        defaults.set(imported.launchAtLogin, forKey: MacPreferences.launchAtLogin)
        defaults.set(imported.showInDock, forKey: MacPreferences.showInDock)
        defaults.set(imported.hotkeyDebugLoggingEnabled, forKey: MacPreferences.hotkeyDebugLoggingEnabled)
        defaults.set(imported.openAIDebugLoggingEnabled, forKey: MacPreferences.openAIDebugLoggingEnabled)
        defaults.set(imported.hotkeyDistinguishModifierSides, forKey: MacPreferences.hotkeyDistinguishModifierSides)
        defaults.set(imported.historyRetentionPeriod, forKey: MacPreferences.historyRetentionPeriod)
        defaults.set(imported.proxyMode, forKey: MacPreferences.proxyMode)
        defaults.set(imported.customProxyScheme, forKey: MacPreferences.customProxyScheme)
        defaults.set(imported.customProxyHost, forKey: MacPreferences.customProxyHost)
        defaults.set(imported.customProxyPort, forKey: MacPreferences.customProxyPort)

        store.saveHotkeyDistinguishModifierSides(imported.hotkeyDistinguishModifierSides)
        store.saveTranslationTargetLanguage(
            TranslationTargetLanguage(rawValue: imported.translationTargetLanguage) ?? .english
        )
        store.saveTranslateSelectedTextOnTranslationHotkey(imported.translateSelectedTextOnTranslationHotkey)
        store.saveHistoryRetentionPeriod(
            HistoryRetentionPeriod(rawValue: imported.historyRetentionPeriod) ?? .thirtyDays
        )
        store.savePersonalDictionary(imported.personalDictionary)
    }
}
#endif
