#if os(macOS)
import AppKit
import Foundation
import Testing

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
        sourceStore.saveProxySettings(
            .init(
                mode: .custom,
                customScheme: .https,
                customHost: "proxy.example.com",
                customPort: 8443
            )
        )
        sourceStore.saveTranslationTargetLanguage(.french)
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
        #expect(targetStore.loadTranslationTargetLanguage() == .french)
        #expect(targetStore.loadPersonalDictionary() == ["OpenAI", "Groq"])
        #expect(targetStore.loadProxySettings().mode == .custom)
        #expect(targetStore.loadProxySettings().customScheme == .https)
        #expect(targetStore.loadProxySettings().customHost == "proxy.example.com")
        #expect(targetStore.loadProxySettings().customPort == 8443)
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

    @Test func exportDataIncludesProxyFields() throws {
        let defaults = TestSupport.makeUserDefaults()
        let store = DictationSettingsStore(defaults: defaults, secretStore: TestSecretStore())
        store.saveProxySettings(
            .init(mode: .disabled, customScheme: .http, customHost: "", customPort: nil)
        )

        let data = try MacConfigurationTransferManager.exportData(using: store, defaults: defaults)
        let payload = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        #expect(payload["proxyMode"] as? String == NetworkProxyMode.disabled.rawValue)
        #expect(payload["customProxyScheme"] as? String == CustomProxyScheme.http.rawValue)
        #expect(payload["customProxyHost"] as? String == "")
        #expect(payload["customProxyPort"] == nil)
    }
}
#endif
