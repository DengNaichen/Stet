#if os(macOS)
    import Combine
    import Foundation
    import AppKit

    @MainActor
    final class MacAudioSettingsViewModel: ObservableObject {
        let deviceManager: AudioDeviceSelectionManager
        let microphoneTestViewModel: MicrophoneTestViewModel
        @Published var localTranscriptionEngine: StoredTranscriptionEngine = .default {
            didSet {
                guard hasLoadedState, oldValue != localTranscriptionEngine else { return }
                settingsStore.saveTranscriptionEngine(localTranscriptionEngine)
            }
        }

        @Published private(set) var isWhisperDownloaded = false
        @Published private(set) var isWhisperDownloading = false
        @Published private(set) var whisperErrorMessage: String?

        @Published private(set) var isParakeetDownloaded = false
        @Published private(set) var isParakeetDownloading = false
        @Published private(set) var parakeetErrorMessage: String?

        @Published private(set) var isSenseVoiceDownloaded = false
        @Published private(set) var isSenseVoiceDownloading = false
        @Published private(set) var senseVoiceErrorMessage: String?

        private let settingsStore: DictationSettingsStore
        private var hasLoadedState = false

        private let localWhisperModelManager: LocalWhisperModelManager
        private let fluidAudioModelManager: FluidAudioModelManager
        private let sherpaOnnxSenseVoiceModelManager: SherpaOnnxSenseVoiceModelManager

        init(
            deviceManager: AudioDeviceSelectionManager = .shared,
            microphoneTestService: MicrophoneTestService = DefaultMicrophoneTestService.shared,
            settingsStore: DictationSettingsStore = DictationSettingsStore(),
            configuration: any ModelStorageConfiguration = UserDefaultsModelStorage()
        ) {
            self.deviceManager = deviceManager
            self.microphoneTestViewModel = MicrophoneTestViewModel(microphoneTestService: microphoneTestService)
            self.settingsStore = settingsStore
            self.localWhisperModelManager = LocalWhisperModelManager(configuration: configuration)
            self.fluidAudioModelManager = FluidAudioModelManager()
            self.sherpaOnnxSenseVoiceModelManager = SherpaOnnxSenseVoiceModelManager(configuration: configuration)
        }

        func onAppear() {
            hasLoadedState = false
            deviceManager.refreshDevices()
            AudioDeviceChangeMonitor.shared.startMonitoring()

            isWhisperDownloaded = (try? localWhisperModelManager.defaultModelReady()) ?? false
            isParakeetDownloaded = fluidAudioModelManager.isModelDownloaded()
            isSenseVoiceDownloaded = sherpaOnnxSenseVoiceModelManager.isModelDownloaded()
            localTranscriptionEngine = settingsStore.loadTranscriptionEngine()
            hasLoadedState = true
        }

        func onDisappear() {
            AudioDeviceChangeMonitor.shared.stopMonitoring()
        }

        var localTranscriptionEngineOptions: [StoredTranscriptionEngine] {
            StoredTranscriptionEngine.allCases
        }

        func downloadWhisperModel() {
            guard !isWhisperDownloading, !isWhisperDownloaded else { return }
            isWhisperDownloading = true
            whisperErrorMessage = nil

            Task { [localWhisperModelManager] in
                do {
                    try await localWhisperModelManager.installDefaultModel()
                    await MainActor.run {
                        self.isWhisperDownloaded = (try? localWhisperModelManager.defaultModelReady()) ?? false
                        self.isWhisperDownloading = false
                    }
                } catch {
                    await MainActor.run {
                        self.whisperErrorMessage = error.localizedDescription
                        self.isWhisperDownloading = false
                    }
                }
            }
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
                    }
                }
            }
        }

        func downloadSenseVoiceModel() {
            guard !isSenseVoiceDownloading, !isSenseVoiceDownloaded else { return }
            isSenseVoiceDownloading = true
            senseVoiceErrorMessage = nil

            Task { [sherpaOnnxSenseVoiceModelManager] in
                do {
                    try await sherpaOnnxSenseVoiceModelManager.installDefaultModel()
                    await MainActor.run {
                        self.isSenseVoiceDownloaded = sherpaOnnxSenseVoiceModelManager.isModelDownloaded()
                        self.isSenseVoiceDownloading = false
                    }
                } catch {
                    await MainActor.run {
                        self.senseVoiceErrorMessage = error.localizedDescription
                        self.isSenseVoiceDownloading = false
                    }
                }
            }
        }

        func openWhisperFolder() {
            revealInFinder(urlProvider: { try self.localWhisperModelManager.defaultModelURL() })
        }

        func openParakeetFolder() {
            revealInFinder(urlProvider: { self.fluidAudioModelManager.cacheDirectoryURL() })
        }

        func openSenseVoiceFolder() {
            revealInFinder(urlProvider: { try self.sherpaOnnxSenseVoiceModelManager.defaultModelURL() })
        }

        private func revealInFinder(urlProvider: @escaping () throws -> URL) {
            do {
                let url = try urlProvider().deletingLastPathComponent()
                NSWorkspace.shared.open(url)
            } catch {}
        }
    }
#endif
