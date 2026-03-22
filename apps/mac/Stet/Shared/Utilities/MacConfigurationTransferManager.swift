#if os(macOS)
import AppKit
import Foundation
import StetVisuals
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
        var pauseMediaDuringDictation: Bool
        var transcriptionProvider: String
        var aiExecutionMode: String?
        var rewriteEnabled: Bool
        var dictationLanguageMode: String
        var interactionSoundsEnabled: Bool
        var interactionSoundPreset: String
        var shaderTheme: String?
        var launchAtLogin: Bool
        var showInDock: Bool
        var hotkeyDistinguishModifierSides: Bool
        var personalDictionary: [String]
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
        return ExportedConfiguration(
            version: 8,
            pauseMediaDuringDictation: defaults.bool(forKey: MacPreferences.pauseMediaDuringDictation),
            transcriptionProvider: DictationProvider(
                rawValue: defaults.string(forKey: MacPreferences.transcriptionProvider) ?? ""
            )?.rawValue ?? DictationProvider.openAI.rawValue,
            aiExecutionMode: store.loadExecutionMode().rawValue,
            rewriteEnabled: defaults.bool(forKey: MacPreferences.rewriteEnabled),
            dictationLanguageMode: store.loadDictationLanguageMode().rawValue,
            interactionSoundsEnabled: defaults.object(forKey: MacPreferences.interactionSoundsEnabled) as? Bool ?? true,
            interactionSoundPreset: defaults.string(forKey: MacPreferences.interactionSoundPreset) ?? InteractionSoundPreset.soft.rawValue,
            shaderTheme: defaults.string(forKey: MacPreferences.shaderTheme) ?? MacDictationShaderTheme.defaultTheme.rawValue,
            launchAtLogin: defaults.object(forKey: MacPreferences.launchAtLogin) as? Bool ?? false,
            showInDock: defaults.object(forKey: MacPreferences.showInDock) as? Bool ?? false,
            hotkeyDistinguishModifierSides: store.loadHotkeyDistinguishModifierSides(),
            personalDictionary: store.loadPersonalDictionary(),
            hotkeyDebugLoggingEnabled: defaults.object(forKey: MacPreferences.hotkeyDebugLoggingEnabled) as? Bool ?? false,
            openAIDebugLoggingEnabled: defaults.object(forKey: MacPreferences.openAIDebugLoggingEnabled) as? Bool ?? false,
            openAIAPIKeyPlaceholder: store.loadAPIKey(for: store.loadProvider()).isEmpty ? "" : "set-manually"
        )
    }

    private static func apply(
        _ imported: ExportedConfiguration,
        using store: DictationSettingsStore,
        defaults: UserDefaults
    ) {
        defaults.set(imported.pauseMediaDuringDictation, forKey: MacPreferences.pauseMediaDuringDictation)
        defaults.set(
            DictationProvider(rawValue: imported.transcriptionProvider)?.rawValue ?? DictationProvider.openAI.rawValue,
            forKey: MacPreferences.transcriptionProvider
        )
        defaults.set(
            AIExecutionMode(rawValue: imported.aiExecutionMode ?? "")?.rawValue ?? AIExecutionMode.automatic.rawValue,
            forKey: MacPreferences.aiExecutionMode
        )
        defaults.set(imported.rewriteEnabled, forKey: MacPreferences.rewriteEnabled)
        defaults.set(imported.dictationLanguageMode, forKey: MacPreferences.dictationLanguageMode)
        defaults.set(imported.interactionSoundsEnabled, forKey: MacPreferences.interactionSoundsEnabled)
        defaults.set(imported.interactionSoundPreset, forKey: MacPreferences.interactionSoundPreset)
        defaults.set(
            MacDictationShaderTheme(rawValue: imported.shaderTheme ?? "")?.rawValue
                ?? MacDictationShaderTheme.defaultTheme.rawValue,
            forKey: MacPreferences.shaderTheme
        )
        defaults.set(imported.launchAtLogin, forKey: MacPreferences.launchAtLogin)
        defaults.set(imported.showInDock, forKey: MacPreferences.showInDock)
        defaults.set(imported.hotkeyDebugLoggingEnabled, forKey: MacPreferences.hotkeyDebugLoggingEnabled)
        defaults.set(imported.openAIDebugLoggingEnabled, forKey: MacPreferences.openAIDebugLoggingEnabled)
        defaults.set(imported.hotkeyDistinguishModifierSides, forKey: MacPreferences.hotkeyDistinguishModifierSides)

        store.saveHotkeyDistinguishModifierSides(imported.hotkeyDistinguishModifierSides)
        store.saveExecutionMode(
            AIExecutionMode(rawValue: imported.aiExecutionMode ?? "") ?? .automatic
        )
        store.saveDictationLanguageMode(
            DictationLanguageMode(rawValue: imported.dictationLanguageMode) ?? .automatic
        )
        store.savePersonalDictionary(imported.personalDictionary)
    }
}
#endif
