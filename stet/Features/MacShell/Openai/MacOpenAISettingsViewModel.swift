#if os(macOS)
    import AppKit
    import Combine
    import Foundation
    import UniformTypeIdentifiers

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

        @Published var localTranscriptionEngine: StoredTranscriptionEngine = .default {
            didSet {
                guard hasLoadedState, oldValue != localTranscriptionEngine else { return }
                settingsStore.saveTranscriptionEngine(localTranscriptionEngine)
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
            localWhisperNeedsAttention || (isRewriteEnabled && !missingRequiredProviders.isEmpty)
        }

        func load() {
            hasLoadedState = false
            isRewriteEnabled = settingsStore.loadRewriteEnabled()
            rewriteProvider = settingsStore.loadRewriteProvider()
            dictationLanguageMode = settingsStore.loadDictationLanguageMode()
            openAIAPIKey = settingsStore.loadAPIKey(for: .openAI)
            groqAPIKey = settingsStore.loadAPIKey(for: .groq)
            localWhisperCustomPath =
                UserDefaults.standard.string(forKey: MacPreferences.localWhisperModelPath) ?? ""
            isParakeetDownloaded = fluidAudioModelManager.isModelDownloaded()
            localTranscriptionEngine = settingsStore.loadTranscriptionEngine()
            hasLoadedState = true
        }

        var localTranscriptionEngineOptions: [StoredTranscriptionEngine] {
            StoredTranscriptionEngine.allCases
        }

        func isEngineSelectable(_ engine: StoredTranscriptionEngine) -> Bool {
            switch engine {
            case .localWhisper:
                return true
            case .fluidAudio:
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
