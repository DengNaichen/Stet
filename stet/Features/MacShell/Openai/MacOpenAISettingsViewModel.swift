#if os(macOS)
    import AppKit
    import Combine
    import Foundation
    import UniformTypeIdentifiers

    @MainActor
    final class MacOpenAISettingsViewModel: ObservableObject {
        @Published var executionMode: AIExecutionMode = .byok {
            didSet {
                guard hasLoadedState else { return }
                settingsStore.saveExecutionMode(executionMode)
            }
        }
        @Published var isRewriteEnabled = true {
            didSet {
                guard hasLoadedState else { return }
                settingsStore.saveRewriteEnabled(isRewriteEnabled)
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
        @Published var dictationLanguageMode: DictationLanguageMode = .automatic {
            didSet {
                guard hasLoadedState else { return }
                settingsStore.saveDictationLanguageMode(dictationLanguageMode)
            }
        }
        @Published var localWhisperCustomPath: String = ""

        private let settingsStore: DictationSettingsStore
        private let localWhisperModelManager: LocalWhisperModelManager
        private var hasLoadedState = false

        init(
            settingsStore: DictationSettingsStore = DictationSettingsStore(),
            localWhisperModelManager: LocalWhisperModelManager = LocalWhisperModelManager()
        ) {
            self.settingsStore = settingsStore
            self.localWhisperModelManager = localWhisperModelManager
        }

        var connectionNeedsAttention: Bool {
            switch executionMode {
            case .managed:
                return true
            case .byok:
                return localWhisperNeedsAttention || (isRewriteEnabled && !missingRequiredProviders.isEmpty)
            }
        }

        func load() {
            hasLoadedState = false
            executionMode = settingsStore.loadExecutionMode()
            isRewriteEnabled = settingsStore.loadRewriteEnabled()
            rewriteProvider = settingsStore.loadRewriteProvider()
            dictationLanguageMode = settingsStore.loadDictationLanguageMode()
            openAIAPIKey = settingsStore.loadAPIKey(for: .openAI)
            groqAPIKey = settingsStore.loadAPIKey(for: .groq)
            localWhisperCustomPath =
                UserDefaults.standard.string(forKey: MacPreferences.localWhisperModelPath) ?? ""
            hasLoadedState = true
        }

        @MainActor
        func selectLocalWhisperModel() {
            let panel = NSOpenPanel()
            panel.title = "Select Whisper Model File"
            panel.message = "Choose a ggml .bin model file"
            panel.allowedContentTypes = [.data]
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false
            panel.canChooseFiles = true

            if panel.runModal() == .OK, let url = panel.url {
                let path = url.path
                LocalWhisperModelManager.saveCustomModelPath(path)
                localWhisperCustomPath = path
            }
        }

        func clearLocalWhisperModel() {
            LocalWhisperModelManager.saveCustomModelPath(nil)
            objectWillChange.send()
        }

        func openLocalWhisperFolder() {
            do {
                let url = try localWhisperModelManager.defaultModelURL().deletingLastPathComponent()
                NSWorkspace.shared.open(url)
            } catch {
                // Silently fail if unable to resolve path
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

        enum UnifiedAIProvider: String, CaseIterable, Identifiable {
            case stet
            case openAI
            case groq

            var id: String { rawValue }
            var displayName: String {
                switch self {
                case .stet: return "Stet (Managed)"
                case .openAI: return "OpenAI"
                case .groq: return "Groq"
                }
            }
        }

        var unifiedProvider: UnifiedAIProvider {
            get {
                if executionMode == .managed { return .stet }
                switch rewriteProvider {
                case .openAI: return .openAI
                case .groq: return .groq
                }
            }
            set {
                switch newValue {
                case .stet:
                    executionMode = .managed
                case .openAI:
                    executionMode = .byok
                    rewriteProvider = .openAI
                case .groq:
                    executionMode = .byok
                    rewriteProvider = .groq
                }
            }
        }

        var visibleCredentialProviders: [DictationProvider] {
            guard executionMode != .managed, isRewriteEnabled else { return [] }
            return [rewriteProvider]
        }

        var localWhisperStatusMessage: String {
            localWhisperModelManager.statusMessage()
        }

        var localWhisperNeedsAttention: Bool {
            localWhisperModelManager.needsAttention()
        }

        func credentialFieldTitle(for provider: DictationProvider) -> String {
            "\(provider.displayName) access key"
        }

        func credentialPlaceholder(for provider: DictationProvider) -> String {
            provider.apiKeyPlaceholder
        }

        var missingCredentialMessage: String? {
            switch executionMode {
            case .managed:
                return "Sign in to use Stet account dictation."
            case .byok:
                guard isRewriteEnabled else { return nil }
                let providerList = missingRequiredProviders.map(\.displayName).joined(separator: " and ")
                guard !providerList.isEmpty else { return nil }
                return
                    "Add \(providerList) API key\(missingRequiredProviders.count == 1 ? "" : "s") before using transcript improvement."
            }
        }

        var isCredentialEditingDisabled: Bool {
            executionMode == .managed
        }

        private var missingRequiredProviders: [DictationProvider] {
            requiredProviders.filter { apiKey(for: $0).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }

        private var requiredProviders: [DictationProvider] {
            switch executionMode {
            case .managed:
                return []
            case .byok:
                return directProviders
            }
        }

        private var directProviders: [DictationProvider] {
            [rewriteProvider]
        }
    }

#endif
