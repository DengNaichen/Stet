#if os(macOS)
    import AppKit
    import Combine
    import Foundation

    @MainActor
    final class MacOpenAISettingsViewModel: ObservableObject {
        @Published var isRewriteEnabled = true {
            didSet {
                guard hasLoadedState else { return }
                settingsStore.saveRewriteEnabled(isRewriteEnabled)
                AnalyticsService.track("rewrite_toggled", parameters: ["enabled": isRewriteEnabled ? "true" : "false"])
            }
        }
        @Published var rewriteProvider: DictationProvider = .openAI {
            didSet {
                guard hasLoadedState else { return }
                settingsStore.saveRewriteProvider(rewriteProvider)
                AnalyticsService.track(
                    "provider_changed",
                    parameters: [
                        "transcription_provider": settingsStore.loadTranscriptionProvider().rawValue,
                        "rewrite_provider": rewriteProvider.rawValue,
                    ])
            }
        }
        @Published var openAIAPIKey = ""
        @Published var groqAPIKey = ""

        private let settingsStore: DictationSettingsStore
        private var hasLoadedState = false

        init(
            settingsStore: DictationSettingsStore = DictationSettingsStore()
        ) {
            self.settingsStore = settingsStore
        }

        var connectionNeedsAttention: Bool {
            isRewriteEnabled && !missingRequiredProviders.isEmpty
        }

        func load() {
            hasLoadedState = false
            isRewriteEnabled = settingsStore.loadRewriteEnabled()
            rewriteProvider = settingsStore.loadRewriteProvider()
            openAIAPIKey = settingsStore.loadAPIKey(for: .openAI)
            groqAPIKey = settingsStore.loadAPIKey(for: .groq)
            hasLoadedState = true
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
            case .appleIntelligence:
                return ""
            }
        }

        func setAPIKey(_ apiKey: String, for provider: DictationProvider) {
            switch provider {
            case .openAI:
                openAIAPIKey = apiKey
            case .groq:
                groqAPIKey = apiKey
            case .appleIntelligence:
                break
            }
        }

        enum UnifiedAIProvider: String, CaseIterable, Identifiable {
            case openAI
            case groq
            case appleIntelligence

            var id: String { rawValue }
            var displayName: String {
                switch self {
                case .openAI: return "OpenAI"
                case .groq: return "Groq"
                case .appleIntelligence: return "Apple Intelligence"
                }
            }
        }

        var unifiedProvider: UnifiedAIProvider {
            get {
                switch rewriteProvider {
                case .openAI: return .openAI
                case .groq: return .groq
                case .appleIntelligence: return .appleIntelligence
                }
            }
            set {
                switch newValue {
                case .openAI:
                    rewriteProvider = .openAI
                case .groq:
                    rewriteProvider = .groq
                case .appleIntelligence:
                    rewriteProvider = .appleIntelligence
                }
            }
        }

        var visibleCredentialProviders: [DictationProvider] {
            guard isRewriteEnabled else { return [] }
            guard rewriteProvider.requiresAPIKey else { return [] }
            return [rewriteProvider]
        }

        func credentialFieldTitle(for provider: DictationProvider) -> String {
            "\(provider.displayName) access key"
        }

        func credentialPlaceholder(for provider: DictationProvider) -> String {
            provider.apiKeyPlaceholder
        }

        var missingCredentialMessage: String? {
            guard isRewriteEnabled else { return nil }
            let providerList = missingRequiredProviders.map(\.displayName).joined(separator: " and ")
            guard !providerList.isEmpty else { return nil }
            return
                "Add \(providerList) API key\(missingRequiredProviders.count == 1 ? "" : "s") before using transcript improvement."
        }

        private var missingRequiredProviders: [DictationProvider] {
            requiredProviders.filter { apiKey(for: $0).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }

        private var requiredProviders: [DictationProvider] {
            rewriteProvider.requiresAPIKey ? [rewriteProvider] : []
        }

        private var directProviders: [DictationProvider] {
            rewriteProvider.requiresAPIKey ? [rewriteProvider] : []
        }
    }

#endif
