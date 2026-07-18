#if os(macOS)
    import Combine
    import StetCore
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

        @Published private(set) var isSenseVoiceDownloaded = false
        @Published private(set) var isSenseVoiceDownloading = false
        @Published private(set) var senseVoiceErrorMessage: String?

        private let settingsStore: DictationSettingsStore
        private var hasLoadedState = false

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
            self.sherpaOnnxSenseVoiceModelManager = SherpaOnnxSenseVoiceModelManager(configuration: configuration)
        }

        func onAppear() {
            hasLoadedState = false
            deviceManager.refreshDevices()
            AudioDeviceChangeMonitor.shared.startMonitoring()

            isSenseVoiceDownloaded = sherpaOnnxSenseVoiceModelManager.isModelDownloaded()
            localTranscriptionEngine = .sherpaOnnxSenseVoice
            settingsStore.saveTranscriptionEngine(.sherpaOnnxSenseVoice)
            hasLoadedState = true
        }

        func onDisappear() {
            AudioDeviceChangeMonitor.shared.stopMonitoring()
        }

        var localTranscriptionEngineOptions: [StoredTranscriptionEngine] {
            [.sherpaOnnxSenseVoice]
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
