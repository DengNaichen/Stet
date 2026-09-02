#if os(macOS)
    import AppKit
    import StetAI
    import StetCore
    import Combine
    import Foundation

    @MainActor
    final class MacOpenAISettingsViewModel: ObservableObject {
        enum ModelProbeState: Equatable {
            case idle
            case loading
            case loaded(Int)
            case failed(String)
        }

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
        @Published var customAPIKey = ""
        @Published var customBaseURL = "" {
            didSet {
                guard hasLoadedState else { return }
                settingsStore.saveCustomRewriteBaseURL(customBaseURL)
            }
        }
        @Published var customModelID = "" {
            didSet {
                guard hasLoadedState else { return }
                settingsStore.saveCustomRewriteModelID(customModelID)
            }
        }
        @Published var discoveredCustomModels: [String] = []
        @Published var customModelProbeState: ModelProbeState = .idle
        @Published var selectedModel: RewriteModel = .gpt56Luna

        private let settingsStore: DictationSettingsStore
        private let modelProbe: any OpenAICompatibleModelProbing
        private var hasLoadedState = false

        init(
            settingsStore: DictationSettingsStore = DictationSettingsStore(),
            modelProbe: any OpenAICompatibleModelProbing = OpenAICompatibleModelProbe()
        ) {
            self.settingsStore = settingsStore
            self.modelProbe = modelProbe
        }

        var connectionNeedsAttention: Bool {
            guard isRewriteEnabled else { return false }
            if rewriteProvider == .custom {
                return !hasUsableCustomEndpoint
            }
            return !missingRequiredProviders.isEmpty
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
            customAPIKey = settingsStore.loadAPIKey(for: .custom)
            customBaseURL = settingsStore.loadCustomRewriteBaseURL()
            customModelID = settingsStore.loadCustomRewriteModelID()
            discoveredCustomModels = settingsStore.loadCustomRewriteDiscoveredModels()
            selectedModel = settingsStore.loadSelectedModel(for: rewriteProvider) ?? .default(for: rewriteProvider)

            // Safety check: If the loaded provider is disabled (e.g. Apple Intelligence on old macOS)
            // or retired from rewrite (Groq, Doubao, Anthropic), fallback to OpenAI.
            if rewriteProvider == .groq || rewriteProvider == .doubao || rewriteProvider == .anthropic
                || unifiedProvider.isDisabled
            {
                rewriteProvider = .openAI
                selectedModel = .gpt56Luna
                settingsStore.saveRewriteProvider(.openAI)
            }

            hasLoadedState = true
        }

        func saveCustomEndpoint() {
            settingsStore.saveCustomRewriteBaseURL(customBaseURL)
            settingsStore.saveCustomRewriteModelID(customModelID)
            settingsStore.saveCustomRewriteDiscoveredModels(discoveredCustomModels)
            saveCredential(for: .custom)
        }

        func loadCustomModels() async {
            customModelProbeState = .loading
            do {
                let url = try OpenAICompatibleBaseURL.normalize(customBaseURL)
                let models = try await modelProbe.listModels(
                    baseURL: url,
                    apiKey: apiKey(for: .custom)
                )
                discoveredCustomModels = models
                settingsStore.saveCustomRewriteBaseURL(customBaseURL)
                settingsStore.saveCustomRewriteDiscoveredModels(models)
                if customModelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    let first = models.first
                {
                    customModelID = first
                }
                try settingsStore.saveAPIKey(
                    apiKey(for: .custom).trimmingCharacters(in: .whitespacesAndNewlines),
                    for: .custom
                )
                customModelProbeState = .loaded(models.count)
            } catch {
                customModelProbeState = .failed(error.localizedDescription)
            }
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
            case .custom:
                return customAPIKey
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
            case .custom:
                customAPIKey = apiKey
            case .appleIntelligence:
                break
            }
        }

        enum UnifiedAIProvider: String, CaseIterable, Identifiable {
            case openAI
            case google
            case appleIntelligence
            case deepSeek
            case qwen
            case glm
            case custom

            var id: String { rawValue }
            var displayName: String {
                switch self {
                case .openAI: return "OpenAI"
                case .google: return "Google"
                case .appleIntelligence: return "Apple Intelligence (Beta)"
                case .deepSeek: return "DeepSeek"
                case .qwen: return "Qwen"
                case .glm: return "GLM"
                case .custom: return NSLocalizedString("Custom", comment: "")
                }
            }

            var isDisabled: Bool {
                switch self {
                case .appleIntelligence:
                    // Only enabled on macOS 26.0+
                    if #available(macOS 26.0, *) {
                        return false
                    } else {
                        return true
                    }
                case .openAI, .google, .deepSeek, .custom:
                    return false
                case .qwen, .glm:
                    // These are placeholders for now
                    return true
                }
            }
        }

        var unifiedProvider: UnifiedAIProvider {
            get {
                switch rewriteProvider {
                case .openAI: return .openAI
                case .google: return .google
                case .appleIntelligence: return .appleIntelligence
                case .deepSeek: return .deepSeek
                case .qwen: return .qwen
                case .glm: return .glm
                case .custom: return .custom
                case .groq, .doubao, .anthropic: return .openAI
                }
            }
            set {
                guard !newValue.isDisabled else { return }
                switch newValue {
                case .openAI:
                    rewriteProvider = .openAI
                case .google:
                    rewriteProvider = .google
                case .appleIntelligence:
                    rewriteProvider = .appleIntelligence
                case .deepSeek:
                    rewriteProvider = .deepSeek
                case .qwen:
                    rewriteProvider = .qwen
                case .glm:
                    rewriteProvider = .glm
                case .custom:
                    rewriteProvider = .custom
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
            if rewriteProvider == .custom {
                guard !hasUsableCustomEndpoint else { return nil }
                return "Add a base URL and model ID before using transcript improvement."
            }
            let providerList = missingRequiredProviders.map(\.displayName).joined(separator: " and ")
            guard !providerList.isEmpty else { return nil }
            return
                "Add \(providerList) API key\(missingRequiredProviders.count == 1 ? "" : "s") before using transcript improvement."
        }

        private var hasUsableCustomEndpoint: Bool {
            let modelID = customModelID.trimmingCharacters(in: .whitespacesAndNewlines)
            return (try? OpenAICompatibleBaseURL.normalize(customBaseURL)) != nil && !modelID.isEmpty
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
