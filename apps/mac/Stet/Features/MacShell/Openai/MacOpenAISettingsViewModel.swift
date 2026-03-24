#if os(macOS)
    import Combine
    import Foundation

    @MainActor
    final class MacOpenAISettingsViewModel: ObservableObject {
        @Published var executionMode: AIExecutionMode = .automatic {
            didSet {
                guard hasLoadedState else { return }
                settingsStore.saveExecutionMode(executionMode)
            }
        }
        @Published var transcriptionProvider: DictationProvider = .openAI {
            didSet {
                guard hasLoadedState else { return }
                settingsStore.saveTranscriptionProvider(transcriptionProvider)
                rewriteProvider = settingsStore.loadRewriteProvider(defaultingTo: transcriptionProvider)
            }
        }
        @Published var rewriteProvider: DictationProvider = .openAI {
            didSet {
                guard hasLoadedState else { return }
                settingsStore.saveRewriteProvider(rewriteProvider)
            }
        }
        @Published var openAIAPIKey = ""
        @Published var groqAPIKey = ""
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
                return !hasRelaySession
                    && (!unsupportedProviderPairMessage.isNilOrEmpty || !missingRequiredProviders.isEmpty)
            case .managed:
                return !hasRelaySession
            case .byok:
                return !unsupportedProviderPairMessage.isNilOrEmpty || !missingRequiredProviders.isEmpty
            }
        }

        func load() {
            hasLoadedState = false
            executionMode = settingsStore.loadExecutionMode()
            transcriptionProvider = settingsStore.loadTranscriptionProvider()
            rewriteProvider = settingsStore.loadRewriteProvider(defaultingTo: transcriptionProvider)
            rewriteEnabled = settingsStore.loadRewriteEnabled()
            dictationLanguageMode = settingsStore.loadDictationLanguageMode()
            openAIAPIKey = settingsStore.loadAPIKey(for: .openAI)
            groqAPIKey = settingsStore.loadAPIKey(for: .groq)
            hasLoadedState = true
        }

        var connectionStatusText: String {
            if unsupportedProviderPairMessage != nil {
                return "Unsupported Pair"
            }

            switch executionMode {
            case .automatic:
                return hasRelaySession ? "Relay Active" : (connectionNeedsAttention ? "Needs Setup" : "Ready")
            case .managed:
                return hasRelaySession ? "Relay Active" : "Sign In Required"
            case .byok:
                return connectionNeedsAttention ? "Needs Setup" : "Ready"
            }
        }

        func saveCredential(for provider: DictationProvider) {
            let trimmedKey = apiKey(for: provider).trimmingCharacters(in: .whitespacesAndNewlines)

            do {
                try settingsStore.saveAPIKey(trimmedKey, for: provider)
                setAPIKey(trimmedKey, for: provider)
            } catch {}
        }

        func clearCredential(for provider: DictationProvider) {
            setAPIKey("", for: provider)
            saveCredential(for: provider)
        }

        func apiKey(for provider: DictationProvider) -> String {
            switch provider {
            case .openAI:
                return openAIAPIKey
            case .groq:
                return groqAPIKey
            }
        }

        func setAPIKey(_ apiKey: String, for provider: DictationProvider) {
            switch provider {
            case .openAI:
                openAIAPIKey = apiKey
            case .groq:
                groqAPIKey = apiKey
            }
        }

        var visibleCredentialProviders: [DictationProvider] {
            let selectedProviders = [
                transcriptionProvider,
                rewriteEnabled ? rewriteProvider : nil,
            ].compactMap { $0 }

            return DictationProvider.allCases.filter { selectedProviders.contains($0) }
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

        func credentialFieldTitle(for provider: DictationProvider) -> String {
            "\(provider.displayName) access key"
        }

        func credentialPlaceholder(for provider: DictationProvider) -> String {
            provider.apiKeyPlaceholder
        }

        var missingCredentialMessage: String? {
            if let unsupportedProviderPairMessage {
                return unsupportedProviderPairMessage
            }

            let providerList = missingRequiredProviders.map(\.displayName).joined(separator: " and ")
            guard !providerList.isEmpty else { return nil }

            switch executionMode {
            case .automatic:
                guard !hasRelaySession else { return nil }
                return
                    "Add \(providerList) API key\(missingRequiredProviders.count == 1 ? "" : "s") to use direct dictation when you're signed out."
            case .managed:
                return hasRelaySession ? nil : "Sign in with your Stet account to use cloud dictation."
            case .byok:
                return
                    "Add \(providerList) API key\(missingRequiredProviders.count == 1 ? "" : "s") before using direct transcription or transcript improvement."
            }
        }

        var isCredentialEditingDisabled: Bool {
            executionMode == .managed
        }

        private var hasRelaySession: Bool {
            relaySessionProvider()
        }

        private var selectedProviderPair: DictationProviderPair {
            DictationProviderPair(
                transcriptionProvider: transcriptionProvider,
                rewriteProvider: rewriteProvider
            )
        }

        private var unsupportedProviderPairMessage: String? {
            guard rewriteEnabled, !OpenAIConfiguration.isSupportedProviderPair(selectedProviderPair) else {
                return nil
            }

            return "OpenAI transcription with Groq rewrite is not supported as a default BYOK pair on Mac."
        }

        private var missingRequiredProviders: [DictationProvider] {
            requiredProviders.filter { apiKey(for: $0).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }

        private var requiredProviders: [DictationProvider] {
            switch executionMode {
            case .automatic:
                return hasRelaySession ? [] : directProviders
            case .managed:
                return []
            case .byok:
                return directProviders
            }
        }

        private var directProviders: [DictationProvider] {
            let selectedProviders = [
                transcriptionProvider,
                rewriteEnabled ? rewriteProvider : nil,
            ].compactMap { $0 }

            return DictationProvider.allCases.filter { selectedProviders.contains($0) }
        }
    }

    private extension Optional where Wrapped == String {
        var isNilOrEmpty: Bool {
            switch self {
            case .none:
                return true
            case .some(let value):
                return value.isEmpty
            }
        }
    }
#endif
