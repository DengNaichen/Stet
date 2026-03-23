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
    @Published private(set) var credentialMessage = "Your access key is stored securely on this Mac."
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
        apiKey = settingsStore.loadAPIKey(for: provider)
        updateCredentialMessage()
        hasLoadedState = true
    }

    var connectionStatusText: String {
        switch executionMode {
        case .automatic:
            return hasRelaySession ? "Signed in" : (connectionNeedsAttention ? "Needs setup" : "Ready")
        case .managed:
            return hasRelaySession ? "Signed in" : "Sign in required"
        case .byok:
            return connectionNeedsAttention ? "Needs setup" : "Ready"
        }
    }

    func saveCredential() {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            try settingsStore.saveAPIKey(trimmedKey, for: provider)
            apiKey = trimmedKey
            credentialMessage = trimmedKey.isEmpty
                ? "Access key removed from this Mac."
                : "\(provider.displayName) access key saved on this Mac."
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

    var rewriteToggleTitle: String {
        switch executionMode {
        case .automatic:
            return "Improve final transcript automatically"
        case .managed:
            return "Improve final transcript with your Stet account"
        case .byok:
            return "Improve final transcript with your own key"
        }
    }

    var credentialFieldTitle: String {
        "\(provider.displayName) access key"
    }

    var credentialPlaceholder: String {
        provider.apiKeyPlaceholder
    }

    var missingCredentialMessage: String? {
        switch executionMode {
        case .automatic:
            guard !hasRelaySession,
                  apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return "Add a \(provider.displayName) access key to use on-device dictation when you're signed out."
        case .managed:
            return hasRelaySession ? nil : "Sign in with your Stet account to use cloud dictation."
        case .byok:
            guard apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return "Add a \(provider.displayName) access key before using direct transcription or transcript improvement."
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
                credentialMessage = "\(provider.displayName) access key is saved on this Mac for on-device fallback."
            } else if hasRelaySession {
                credentialMessage = "Your Stet account is active for dictation. No on-device key is saved."
            } else {
                credentialMessage = "No \(provider.displayName) access key is saved for on-device fallback."
            }
        case .managed:
            if hasRelaySession {
                credentialMessage = hasCredential
                    ? "A \(provider.displayName) access key is saved on this Mac, but it is not needed while you're signed in."
                    : "Your Stet account is active for dictation."
            } else if hasCredential {
                credentialMessage = "Sign in to use cloud dictation. A \(provider.displayName) access key is saved for later use."
            } else {
                credentialMessage = "Sign in to use cloud dictation. No access key is saved."
            }
        case .byok:
            credentialMessage = hasCredential
                ? "\(provider.displayName) access key is saved on this Mac."
                : "No \(provider.displayName) access key is saved on this Mac."
        }
        credentialMessageIsError = false
    }

    private var hasRelaySession: Bool {
        relaySessionProvider()
    }
}
#endif
