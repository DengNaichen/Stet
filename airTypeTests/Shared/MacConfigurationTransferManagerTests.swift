#if os(macOS)
import AppKit
import Carbon
import Foundation
import Testing

@testable import airType

@MainActor
@Suite("Configuration Transfer", .serialized)
struct MacConfigurationTransferManagerTests {
    @Test func exportAndImportRoundTripPreservesConfiguration() throws {
        let sourceDefaults = TestSupport.makeUserDefaults()
        let sourceSecretStore = TestSecretStore()
        let sourceStore = DictationSettingsStore(defaults: sourceDefaults, secretStore: sourceSecretStore)

        sourceDefaults.set(true, forKey: MacPreferences.showPanelOnLaunch)
        sourceDefaults.set(DictationProvider.openAI.rawValue, forKey: MacPreferences.transcriptionProvider)
        sourceDefaults.set("http://127.0.0.1:54321/functions/v1/relay/v1", forKey: MacPreferences.openAIBaseURL)
        sourceDefaults.set(CustomProxyScheme.https.rawValue, forKey: MacPreferences.customProxyScheme)
        sourceDefaults.set(NetworkProxyMode.custom.rawValue, forKey: MacPreferences.proxyMode)
        sourceDefaults.set("proxy.example.com", forKey: MacPreferences.customProxyHost)
        sourceDefaults.set("8443", forKey: MacPreferences.customProxyPort)
        sourceStore.saveTranslationTargetLanguage(.french)
        sourceStore.savePersonalDictionary(["OpenAI", "Groq"])
        sourceStore.saveAppBranchRules([
            .init(
                name: "Docs",
                prompt: "Follow {{APP_NAME}} style",
                appTargets: [.init(bundleID: "com.apple.Safari", displayName: "Safari")],
                urlPatterns: ["docs.example.com/*"]
            )
        ])
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

        #expect(targetDefaults.bool(forKey: MacPreferences.showPanelOnLaunch))
        #expect(targetDefaults.string(forKey: MacPreferences.transcriptionProvider) == DictationProvider.openAI.rawValue)
        #expect(targetDefaults.string(forKey: MacPreferences.openAIBaseURL) == "http://127.0.0.1:54321/functions/v1/relay/v1")
        #expect(targetStore.loadTranslationTargetLanguage() == .french)
        #expect(targetStore.loadPersonalDictionary() == ["OpenAI", "Groq"])
        #expect(targetStore.loadProxySettings().customHost == "proxy.example.com")
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
