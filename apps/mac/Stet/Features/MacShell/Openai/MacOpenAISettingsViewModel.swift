#if os(macOS)
import Combine
import Foundation

@MainActor
final class MacOpenAISettingsViewModel: ObservableObject {
    @Published var provider: DictationProvider = .openAI {
        didSet {
            guard hasLoadedState else { return }
            settingsStore.saveProvider(provider)
            apiKey = settingsStore.loadAPIKey(for: provider)
            updateCredentialMessage()
        }
    }
    @Published var apiKey = ""
    @Published var rewriteEnabled = false {
        didSet {
            guard hasLoadedState else { return }
            settingsStore.saveRewriteEnabled(rewriteEnabled)
        }
    }
    @Published var translationTargetLanguage: TranslationTargetLanguage = .english {
        didSet {
            guard hasLoadedState else { return }
            settingsStore.saveTranslationTargetLanguage(translationTargetLanguage)
        }
    }
    @Published var translateSelectedTextOnTranslationHotkey = true {
        didSet {
            guard hasLoadedState else { return }
            settingsStore.saveTranslateSelectedTextOnTranslationHotkey(translateSelectedTextOnTranslationHotkey)
        }
    }
    @Published private(set) var credentialMessage = "Stored securely in Keychain."
    @Published private(set) var credentialMessageIsError = false

    private let settingsStore: DictationSettingsStore
    private var hasLoadedState = false

    init(settingsStore: DictationSettingsStore = DictationSettingsStore()) {
        self.settingsStore = settingsStore
    }

    var shouldHighlightMissingCredential: Bool {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func load() {
        hasLoadedState = false
        provider = settingsStore.loadProvider()
        rewriteEnabled = settingsStore.loadRewriteEnabled()
        translationTargetLanguage = settingsStore.loadTranslationTargetLanguage()
        translateSelectedTextOnTranslationHotkey = settingsStore.loadTranslateSelectedTextOnTranslationHotkey()
        apiKey = settingsStore.loadAPIKey(for: provider)
        updateCredentialMessage()
        hasLoadedState = true
    }

    var connectionStatusText: String {
        shouldHighlightMissingCredential ? "Missing Key" : "Configured"
    }

    func saveCredential() {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            try settingsStore.saveAPIKey(trimmedKey, for: provider)
            apiKey = trimmedKey
            credentialMessage = trimmedKey.isEmpty
                ? "Credential removed from Keychain."
                : "\(provider.displayName) API key saved in Keychain."
            credentialMessageIsError = false
        } catch {
            credentialMessage = error.localizedDescription
            credentialMessageIsError = true
        }
    }

    func clearCredential() {
        apiKey = ""
        saveCredential()
    }

    var modelSummary: String {
        let providerDefaults = OpenAIConfiguration.providerDefaults(for: provider)
        return "Stet uses \(providerDefaults.transcriptionModel) for transcription and \(providerDefaults.translationModel) for translation and rewrite."
    }

    var providerDescription: String {
        "Choose between OpenAI and Groq. Stet manages the endpoint and model selection automatically."
    }

    var rewriteToggleTitle: String {
        "Rewrite final transcript with \(provider.displayName)"
    }

    var credentialFieldTitle: String {
        "\(provider.displayName) API key"
    }

    var credentialPlaceholder: String {
        provider.apiKeyPlaceholder
    }

    private func updateCredentialMessage() {
        credentialMessage = apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Add a \(provider.displayName) API key to enable cloud features."
            : "\(provider.displayName) API key is saved in Keychain."
        credentialMessageIsError = false
    }
}
#endif
