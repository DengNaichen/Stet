#if os(macOS)
    import Combine
    import Foundation

    @MainActor
    final class MacAudioSettingsViewModel: ObservableObject {
        let deviceManager: AudioDeviceSelectionManager
        let microphoneTestViewModel: MicrophoneTestViewModel

        init(
            deviceManager: AudioDeviceSelectionManager = .shared,
            microphoneTestService: MicrophoneTestService = DefaultMicrophoneTestService.shared
        ) {
            self.deviceManager = deviceManager
            self.microphoneTestViewModel = MicrophoneTestViewModel(microphoneTestService: microphoneTestService)
        }

        func onAppear() {
            deviceManager.refreshDevices()
            AudioDeviceChangeMonitor.shared.startMonitoring()
        }

        func onDisappear() {
            AudioDeviceChangeMonitor.shared.stopMonitoring()
        }
    }
#endif
