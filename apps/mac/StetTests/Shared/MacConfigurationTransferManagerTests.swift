#if os(macOS)
import AppKit
import Foundation
import Testing
import StetVisuals

@testable import Stet

@MainActor
@Suite("Configuration Transfer", .serialized)
struct MacConfigurationTransferManagerTests {
    @Test func exportAndImportRoundTripPreservesConfiguration() throws {
        let sourceDefaults = TestSupport.makeUserDefaults()
        let sourceSecretStore = TestSecretStore()
        let sourceStore = DictationSettingsStore(defaults: sourceDefaults, secretStore: sourceSecretStore)

        sourceDefaults.set(true, forKey: MacPreferences.pauseMediaDuringDictation)
        sourceDefaults.set(true, forKey: MacPreferences.showInDock)
        sourceDefaults.set(DictationProvider.openAI.rawValue, forKey: MacPreferences.transcriptionProvider)
        sourceDefaults.set(AIExecutionMode.byok.rawValue, forKey: MacPreferences.aiExecutionMode)
        sourceDefaults.set(MacDictationShaderTheme.sunset.rawValue, forKey: MacPreferences.shaderTheme)
        sourceStore.saveDictationLanguageMode(.primarilyEnglish)
        sourceStore.savePersonalDictionary(["OpenAI", "Groq"])
        try sourceStore.saveOpenAIAPIKey("sk-secret")

        let data = try MacConfigurationTransferManager.exportData(
            using: sourceStore,
            defaults: sourceDefaults
        )

        let targetDefaults = TestSupport.makeUserDefaults()
        let targetSecretStore = TestSecretStore()
        let targetStore = DictationSettingsStore(defaults: targetDefaults, secretStore: targetSecretStore)

        try MacConfigurationTransferManager.importData(
            data,
            using: targetStore,
            defaults: targetDefaults
        )

        #expect(targetDefaults.bool(forKey: MacPreferences.pauseMediaDuringDictation))
        #expect(targetDefaults.bool(forKey: MacPreferences.showInDock))
        #expect(targetDefaults.string(forKey: MacPreferences.transcriptionProvider) == DictationProvider.openAI.rawValue)
        #expect(targetDefaults.string(forKey: MacPreferences.aiExecutionMode) == AIExecutionMode.byok.rawValue)
        #expect(targetDefaults.string(forKey: MacPreferences.shaderTheme) == MacDictationShaderTheme.sunset.rawValue)
        #expect(targetStore.loadExecutionMode() == .byok)
        #expect(targetStore.loadDictationLanguageMode() == .primarilyEnglish)
        #expect(targetStore.loadPersonalDictionary() == ["OpenAI", "Groq"])
        #expect(targetStore.loadOpenAIAPIKey().isEmpty)
    }

    @Test func importDataRejectsInvalidPayload() {
        let defaults = TestSupport.makeUserDefaults()
        let store = DictationSettingsStore(defaults: defaults, secretStore: TestSecretStore())

        #expect(throws: MacConfigurationTransferError.invalidData) {
            try MacConfigurationTransferManager.importData(
                Data("not json".utf8),
                using: store,
                defaults: defaults
            )
        }
    }

}
#endif
