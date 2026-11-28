import Foundation
import Security
import StetAI
import StetCore
import Testing
@testable import StetMobile

struct RewriteSettingsViewModelTests {
    @MainActor
    @Test func dictationEngineIsAppleSpeechOnly() {
        let suiteName = "MobileDictationSettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("senseVoice", forKey: "dictation.engine")

        #expect(MobileDictationEngine.allCases == [.appleSpeech])
        #expect(MobileDictationSettingsStore(defaults: defaults).selectedEngine == .appleSpeech)
        #expect(defaults.string(forKey: "dictation.engine") == "appleSpeech")
    }

    @MainActor
    @Test func speechLanguageSelectionSurvivesStoreRecreation() {
        let suiteName = "SpeechRecognitionSettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SpeechRecognitionSettingsStore(defaults: defaults)
        store.selectedLanguage = .japanese

        let reloadedStore = SpeechRecognitionSettingsStore(defaults: defaults)
        #expect(reloadedStore.selectedLanguage == .japanese)
        #expect(reloadedStore.assetStatus == .checking)
    }

    @MainActor
    @Test func microphoneKeepAliveSelectionPersistsAndNotifiesViewModel() {
        let suiteName = "MicrophoneKeepAliveSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let speechStore = SpeechRecognitionSettingsStore(defaults: defaults)
        #expect(speechStore.microphoneKeepAliveDuration == .twoHours)

        let secretStore = InMemoryDictationSecretStore()
        let rewriteStore = RewriteSettingsStore(defaults: defaults, secretStore: secretStore)
        let viewModel = RewriteSettingsViewModel(
            settingsStore: rewriteStore,
            speechSettingsStore: speechStore,
            validationService: StubCredentialValidator()
        )

        var notifiedDurations: [MicrophoneKeepAliveDuration] = []
        viewModel.onMicrophoneKeepAliveChanged = { notifiedDurations.append($0) }

        viewModel.microphoneKeepAliveDuration = .fiveMinutes
        #expect(notifiedDurations == [.fiveMinutes])
        #expect(MicrophoneKeepAliveDuration.fiveMinutes.timeoutDuration == .seconds(300))

        viewModel.microphoneKeepAliveDuration = .never
        #expect(notifiedDurations == [.fiveMinutes, .never])
        #expect(MicrophoneKeepAliveDuration.never.timeoutDuration == nil)

        let reloadedStore = SpeechRecognitionSettingsStore(defaults: defaults)
        #expect(reloadedStore.microphoneKeepAliveDuration == .never)
    }

    @MainActor
    @Test func rewriteSummaryReflectsEnabledStateAndModelSelection() throws {
        let suiteName = "RewriteSummaryTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settingsStore = RewriteSettingsStore(
            defaults: defaults,
            secretStore: InMemoryDictationSecretStore()
        )
        let viewModel = RewriteSettingsViewModel(
            settingsStore: settingsStore,
            speechSettingsStore: SpeechRecognitionSettingsStore(defaults: defaults),
            validationService: StubCredentialValidator()
        )

        settingsStore.isRewriteEnabled = false
        #expect(viewModel.rewriteSummary == "Off")

        settingsStore.isRewriteEnabled = true
        settingsStore.selectedProvider = .openAI
        settingsStore.selectedModel = RewriteModel.default(for: .openAI)
        #expect(viewModel.rewriteSummary == settingsStore.selectedModel.displayName)

        settingsStore.selectedProvider = .custom
        settingsStore.customModelID = "  my-local-model  "
        #expect(viewModel.rewriteSummary == "my-local-model")
    }

    @MainActor
    @Test func retiredWhisperModelIsRemoved() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StetRetiredModelCleanupTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let modelDirectory =
            directory
            .appendingPathComponent("Stet", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent("Whisper", isDirectory: true)
        try FileManager.default.createDirectory(
            at: modelDirectory,
            withIntermediateDirectories: true
        )
        let modelURL = modelDirectory.appendingPathComponent("model.bin")
        try Data([1]).write(to: modelURL)

        RetiredDictationModelCleanup.removeWhisperModel(
            from: directory,
            fileManager: .default
        )

        #expect(!FileManager.default.fileExists(atPath: modelDirectory.path))
        #expect(FileManager.default.fileExists(atPath: directory.path))
    }

    @MainActor
    @Test func rewriteSettingsStoreUsesSharedCredentialAccount() throws {
        let suiteName = "RewriteSettingsStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let secretStore = InMemoryDictationSecretStore()

        let store = RewriteSettingsStore(defaults: defaults, secretStore: secretStore)
        try store.saveAPIKey("  sk-shared-openai  ", for: .openAI)

        let expectedAccount = DictationCredentialAccount.apiKey(for: .openAI)
        #expect(try secretStore.loadString(forAccount: expectedAccount) == "sk-shared-openai")
        #expect(store.loadAPIKey(for: .openAI) == "sk-shared-openai")
        #expect(store.lastKeychainError == nil)

        try store.saveAPIKey("   ", for: .openAI)
        #expect(try secretStore.loadString(forAccount: expectedAccount) == nil)
        #expect(store.loadAPIKey(for: .openAI) == nil)
    }

    @MainActor
    @Test func refreshSyncedAPIKeyUpdatesInputWithoutClobberingUnsavedEdits() throws {
        let suiteName = "RewriteSettingsSyncRefreshTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let secretStore = InMemoryDictationSecretStore()
        let settingsStore = RewriteSettingsStore(defaults: defaults, secretStore: secretStore)
        let speechStore = SpeechRecognitionSettingsStore(defaults: defaults)
        let viewModel = RewriteSettingsViewModel(
            settingsStore: settingsStore,
            speechSettingsStore: speechStore,
            validationService: StubCredentialValidator()
        )

        #expect(viewModel.apiKeyInput.isEmpty)

        // Simulate an API key synced from macOS via iCloud Keychain.
        let account = DictationCredentialAccount.apiKey(for: .openAI)
        try secretStore.saveString("sk-from-mac", forAccount: account)
        viewModel.refreshSyncedAPIKey()
        #expect(viewModel.apiKeyInput == "sk-from-mac")

        // Unsaved user typing must not be overwritten on foreground refresh.
        viewModel.apiKeyInput = "sk-local-draft"
        try secretStore.saveString("sk-newer-from-mac", forAccount: account)
        viewModel.refreshSyncedAPIKey()
        #expect(viewModel.apiKeyInput == "sk-local-draft")

        // Saving updates the synced baseline so later remote updates apply again.
        viewModel.saveAPIKey()
        #expect(try secretStore.loadString(forAccount: account) == "sk-local-draft")
        try secretStore.saveString("sk-final-from-mac", forAccount: account)
        viewModel.refreshSyncedAPIKey()
        #expect(viewModel.apiKeyInput == "sk-final-from-mac")
    }

    @MainActor
    @Test func keychainSaveErrorsSurfaceInValidationState() async throws {
        let suiteName = "RewriteSettingsKeychainErrorTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let secretStore = InMemoryDictationSecretStore()
        secretStore.saveError = SecretStoreError.unexpectedStatus(errSecAuthFailed)

        let settingsStore = RewriteSettingsStore(defaults: defaults, secretStore: secretStore)
        let speechStore = SpeechRecognitionSettingsStore(defaults: defaults)
        let viewModel = RewriteSettingsViewModel(
            settingsStore: settingsStore,
            speechSettingsStore: speechStore,
            validationService: StubCredentialValidator()
        )

        viewModel.apiKeyInput = "sk-valid-key"
        viewModel.saveAPIKey()

        guard case .failed(let saveMessage) = viewModel.validationState else {
            Issue.record("Expected failed state after Keychain save error")
            return
        }
        #expect(saveMessage.contains("Keychain"))
        #expect(settingsStore.lastKeychainError != nil)

        await viewModel.validateCredential()
        guard case .failed(let validateSaveMessage) = viewModel.validationState else {
            Issue.record("Expected failed state when persisting after validation fails")
            return
        }
        #expect(validateSaveMessage.contains("Keychain"))
    }
}

private final class InMemoryDictationSecretStore: DictationSecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]
    var loadError: Error?
    var saveError: Error?
    var deleteError: Error?

    func loadString(forAccount account: String) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        if let loadError {
            throw loadError
        }
        return values[account]
    }

    func saveString(_ value: String, forAccount account: String) throws {
        lock.lock()
        defer { lock.unlock() }
        if let saveError {
            throw saveError
        }
        values[account] = value
    }

    func deleteString(forAccount account: String) throws {
        lock.lock()
        defer { lock.unlock() }
        if let deleteError {
            throw deleteError
        }
        values.removeValue(forKey: account)
    }
}

private struct StubCredentialValidator: ProviderCredentialValidating {
    let errorToThrow: (any Error)?

    init(errorToThrow: (any Error)? = nil) {
        self.errorToThrow = errorToThrow
    }

    func validateCredential(apiKey _: String, provider _: DictationProvider) async throws {
        if let errorToThrow {
            throw errorToThrow
        }
    }
}
