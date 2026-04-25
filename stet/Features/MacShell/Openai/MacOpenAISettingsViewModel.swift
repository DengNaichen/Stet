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

        @Published private(set) var isParakeetDownloaded = false
        @Published private(set) var isParakeetDownloading = false
        @Published private(set) var parakeetErrorMessage: String?

        @Published var localTranscriptionEngine: LocalTranscriptionEngine = .default {
            didSet {
                guard hasLoadedState, oldValue != localTranscriptionEngine else { return }
                UserDefaults.standard.set(
                    localTranscriptionEngine.rawValue,
                    forKey: MacPreferences.localTranscriptionEngine
                )
            }
        }

        private let settingsStore: DictationSettingsStore
        private let localWhisperModelManager: LocalWhisperModelManager
        private let fluidAudioModelManager: FluidAudioModelManager
        private var hasLoadedState = false

        init(
            settingsStore: DictationSettingsStore = DictationSettingsStore(),
            localWhisperModelManager: LocalWhisperModelManager = LocalWhisperModelManager(),
            fluidAudioModelManager: FluidAudioModelManager = FluidAudioModelManager()
        ) {
            self.settingsStore = settingsStore
            self.localWhisperModelManager = localWhisperModelManager
            self.fluidAudioModelManager = fluidAudioModelManager
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
            isParakeetDownloaded = fluidAudioModelManager.isModelDownloaded()
            localTranscriptionEngine = LocalTranscriptionEngine.current()
            hasLoadedState = true
        }

        var localTranscriptionEngineOptions: [LocalTranscriptionEngine] {
            LocalTranscriptionEngine.allCases
        }

        /// Picker is enabled when the underlying model is actually present so the
        /// user can't switch to Parakeet then immediately fail their next dictation.
        func isEngineSelectable(_ engine: LocalTranscriptionEngine) -> Bool {
            switch engine {
            case .whisper:
                return true
            case .parakeet:
                return isParakeetDownloaded
            }
        }

        var parakeetDisplayName: String {
            FluidAudioModelManager.displayName
        }

        func downloadParakeetModel() {
            guard !isParakeetDownloading, !isParakeetDownloaded else { return }
            isParakeetDownloading = true
            parakeetErrorMessage = nil

            Task { [fluidAudioModelManager] in
                do {
                    try await fluidAudioModelManager.downloadModel()
                    await MainActor.run {
                        self.isParakeetDownloaded = fluidAudioModelManager.isModelDownloaded()
                        self.isParakeetDownloading = false
                    }
                } catch {
                    await MainActor.run {
                        self.parakeetErrorMessage = error.localizedDescription
                        self.isParakeetDownloading = false
                        self.isParakeetDownloaded = fluidAudioModelManager.isModelDownloaded()
                    }
                }
            }
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
            case stet
            case openAI
            case groq
            case appleIntelligence

            var id: String { rawValue }
            var displayName: String {
                switch self {
                case .stet: return "Stet (Managed)"
                case .openAI: return "OpenAI"
                case .groq: return "Groq"
                case .appleIntelligence: return "Apple Intelligence"
                }
            }
        }

        var unifiedProvider: UnifiedAIProvider {
            get {
                if executionMode == .managed { return .stet }
                switch rewriteProvider {
                case .openAI: return .openAI
                case .groq: return .groq
                case .appleIntelligence: return .appleIntelligence
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
                case .appleIntelligence:
                    executionMode = .byok
                    rewriteProvider = .appleIntelligence
                }
            }
        }

        var visibleCredentialProviders: [DictationProvider] {
            guard executionMode != .managed, isRewriteEnabled else { return [] }
            guard rewriteProvider.requiresAPIKey else { return [] }
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
            rewriteProvider.requiresAPIKey ? [rewriteProvider] : []
        }
    }

#endif
