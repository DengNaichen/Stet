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
        @Published var googleAPIKey = ""
        @Published var anthropicAPIKey = ""
        @Published var groqAPIKey = ""
        @Published var deepSeekAPIKey = ""
        @Published var qwenAPIKey = ""
        @Published var glmAPIKey = ""
        @Published var doubaoAPIKey = ""
        @Published var selectedModel: RewriteModel = .gpt54Nano

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
            googleAPIKey = settingsStore.loadAPIKey(for: .google)
            anthropicAPIKey = settingsStore.loadAPIKey(for: .anthropic)
            groqAPIKey = settingsStore.loadAPIKey(for: .groq)
            deepSeekAPIKey = settingsStore.loadAPIKey(for: .deepSeek)
            qwenAPIKey = settingsStore.loadAPIKey(for: .qwen)
            glmAPIKey = settingsStore.loadAPIKey(for: .glm)
            doubaoAPIKey = settingsStore.loadAPIKey(for: .doubao)
            selectedModel = settingsStore.loadSelectedModel(for: rewriteProvider) ?? .default(for: rewriteProvider)
            hasLoadedState = true
        }

        func saveCredential(for provider: DictationProvider) {
            let trimmedKey = apiKey(for: provider).trimmingCharacters(in: .whitespacesAndNewlines)

            do {
                try settingsStore.saveAPIKey(trimmedKey, for: provider)
                settingsStore.saveSelectedModel(selectedModel, for: provider)
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
            case .google:
                return googleAPIKey
            case .anthropic:
                return anthropicAPIKey
            case .groq:
                return groqAPIKey
            case .deepSeek:
                return deepSeekAPIKey
            case .qwen:
                return qwenAPIKey
            case .glm:
                return glmAPIKey
            case .doubao:
                return doubaoAPIKey
            case .appleIntelligence:
                return ""
            }
        }

        func setAPIKey(_ apiKey: String, for provider: DictationProvider) {
            switch provider {
            case .openAI:
                openAIAPIKey = apiKey
            case .google:
                googleAPIKey = apiKey
            case .anthropic:
                anthropicAPIKey = apiKey
            case .groq:
                groqAPIKey = apiKey
            case .deepSeek:
                deepSeekAPIKey = apiKey
            case .qwen:
                qwenAPIKey = apiKey
            case .glm:
                glmAPIKey = apiKey
            case .doubao:
                doubaoAPIKey = apiKey
            case .appleIntelligence:
                break
            }
        }

        enum UnifiedAIProvider: String, CaseIterable, Identifiable {
            case openAI
            case google
            case anthropic
            case appleIntelligence
            case groq
            case deepSeek
            case qwen
            case glm
            case doubao

            var id: String { rawValue }
            var displayName: String {
                switch self {
                case .openAI: return "OpenAI"
                case .google: return "Google"
                case .anthropic: return "Anthropic"
                case .appleIntelligence: return "Apple Intelligence"
                case .groq: return "Groq"
                case .deepSeek: return "DeepSeek"
                case .qwen: return "Qwen"
                case .glm: return "GLM"
                case .doubao: return "Doubao"
                }
            }

            var isDisabled: Bool {
                switch self {
                case .openAI, .google, .anthropic, .appleIntelligence, .groq:
                    return false
                case .deepSeek, .qwen, .glm, .doubao:
                    return true
                }
            }
        }

        var unifiedProvider: UnifiedAIProvider {
            get {
                switch rewriteProvider {
                case .openAI: return .openAI
                case .google: return .google
                case .anthropic: return .anthropic
                case .appleIntelligence: return .appleIntelligence
                case .groq: return .groq
                case .deepSeek: return .deepSeek
                case .qwen: return .qwen
                case .glm: return .glm
                case .doubao: return .doubao
                }
            }
            set {
                guard !newValue.isDisabled else { return }
                switch newValue {
                case .openAI:
                    rewriteProvider = .openAI
                case .google:
                    rewriteProvider = .google
                case .anthropic:
                    rewriteProvider = .anthropic
                case .appleIntelligence:
                    rewriteProvider = .appleIntelligence
                case .groq:
                    rewriteProvider = .groq
                case .deepSeek:
                    rewriteProvider = .deepSeek
                case .qwen:
                    rewriteProvider = .qwen
                case .glm:
                    rewriteProvider = .glm
                case .doubao:
                    rewriteProvider = .doubao
                }
                selectedModel = settingsStore.loadSelectedModel(for: rewriteProvider) ?? .default(for: rewriteProvider)
            }
        }

        var visibleCredentialProviders: [DictationProvider] {
            guard isRewriteEnabled else { return [] }
            guard rewriteProvider.requiresAPIKey else { return [] }
            return [rewriteProvider]
        }

        var availableModels: [RewriteModel] {
            RewriteModel.availableModels(for: rewriteProvider)
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
