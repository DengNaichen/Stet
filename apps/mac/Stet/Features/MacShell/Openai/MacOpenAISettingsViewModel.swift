#if os(macOS)
import Combine
import Foundation

@MainActor
final class MacOpenAISettingsViewModel: ObservableObject {
    @Published var executionMode: AIExecutionMode = .automatic {
        didSet {
            guard hasLoadedState else { return }
            settingsStore.saveExecutionMode(executionMode)
            updateCredentialMessage()
        }
    }
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
    @Published var dictationLanguageMode: DictationLanguageMode = .automatic {
        didSet {
            guard hasLoadedState else { return }
            settingsStore.saveDictationLanguageMode(dictationLanguageMode)
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
    private let relaySessionProvider: @MainActor @Sendable () -> Bool
    private var hasLoadedState = false

    init(
        settingsStore: DictationSettingsStore = DictationSettingsStore(),
        relaySessionProvider: @escaping @MainActor @Sendable () -> Bool = {
            SupabaseService.shared.currentSession != nil
        }
    ) {
        self.settingsStore = settingsStore
        self.relaySessionProvider = relaySessionProvider
    }

    var connectionNeedsAttention: Bool {
        switch executionMode {
        case .automatic:
            return !hasRelaySession && apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .managed:
            return !hasRelaySession
        case .byok:
            return apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    func load() {
        hasLoadedState = false
        executionMode = settingsStore.loadExecutionMode()
        provider = settingsStore.loadProvider()
        rewriteEnabled = settingsStore.loadRewriteEnabled()
        dictationLanguageMode = settingsStore.loadDictationLanguageMode()
        translationTargetLanguage = settingsStore.loadTranslationTargetLanguage()
        translateSelectedTextOnTranslationHotkey = settingsStore.loadTranslateSelectedTextOnTranslationHotkey()
        apiKey = settingsStore.loadAPIKey(for: provider)
        updateCredentialMessage()
        hasLoadedState = true
    }

    var connectionStatusText: String {
        switch executionMode {
        case .automatic:
            return hasRelaySession ? "Relay Active" : (connectionNeedsAttention ? "Missing Key" : "Direct Fallback")
        case .managed:
            return hasRelaySession ? "Relay Only" : "Sign In Required"
        case .byok:
            return connectionNeedsAttention ? "Missing Key" : "Configured"
        }
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
        switch executionMode {
        case .automatic:
            return "Automatic"
        case .managed:
            return "Managed Relay"
        case .byok:
            return "BYOK"
        }
    }

    var providerDescription: String {
        switch executionMode {
        case .automatic:
            return "Automatic"
        case .managed:
            return "Managed Relay"
        case .byok:
            return "BYOK"
        }
    }

    var rewriteToggleTitle: String {
        switch executionMode {
        case .automatic:
            return "Rewriteuselly"
        case .managed:
            return "Rewrite final transcript with Managed Relay"
        case .byok:
            return "Rewrite final transcript with \(provider.displayName)"
        }
    }

    var dictationLanguageDescription: String {
        dictationLanguageMode.subtitle
    }

    var credentialFieldTitle: String {
        "\(provider.displayName) API key"
    }

    var credentialPlaceholder: String {
        provider.apiKeyPlaceholder
    }

    var executionModeDescription: String {
        executionMode.subtitle
    }

    var missingCredentialMessage: String? {
        switch executionMode {
        case .automatic:
            guard !hasRelaySession,
                  apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return "Add a \(provider.displayName) API key to enable local dictation when you are signed out."
        case .managed:
            return hasRelaySession ? nil : "Sign in with your Stet account to use Managed Relay for dictation."
        case .byok:
            guard apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return "Add a \(provider.displayName) API key before using direct transcription, translation, or rewrite."
        }
    }

    var isCredentialEditingDisabled: Bool {
        executionMode == .managed
    }

    private func updateCredentialMessage() {
        let hasCredential = !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        switch executionMode {
        case .automatic:
            if hasCredential {
                credentialMessage = "\(provider.displayName) API key is saved in Keychain for local fallback."
            } else if hasRelaySession {
                credentialMessage = "Managed Relay is active for dictation. No local fallback key is currently saved."
            } else {
                credentialMessage = "No \(provider.displayName) API key is saved for local fallback."
            }
        case .managed:
            if hasRelaySession {
                credentialMessage = hasCredential
                    ? "A \(provider.displayName) API key is saved in Keychain but ignored by Managed Relay."
                    : "Managed Relay is active for dictation."
            } else if hasCredential {
                credentialMessage = "Sign in to use Managed Relay. A \(provider.displayName) API key is saved for future Automatic fallback or BYOK use."
            } else {
                credentialMessage = "Sign in to use Managed Relay. No local provider API key is saved."
            }
        case .byok:
            credentialMessage = hasCredential
                ? "\(provider.displayName) API key is saved in Keychain."
                : "No \(provider.displayName) API key is saved in Keychain."
        }
        credentialMessageIsError = false
    }

    private var hasRelaySession: Bool {
        relaySessionProvider()
    }
}
#endif
