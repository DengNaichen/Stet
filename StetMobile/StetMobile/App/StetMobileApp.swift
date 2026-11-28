import SwiftUI
import StetAI

@main
struct StetMobileApp: App {
    @StateObject private var rewriteSettingsStore: RewriteSettingsStore
    @StateObject private var speechSettingsStore: SpeechRecognitionSettingsStore
    @StateObject private var rewriteSettingsViewModel: RewriteSettingsViewModel
    @StateObject private var appViewModel: AppViewModel
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var viewModel: SenseVoiceViewModel

    init() {
        RetiredDictationModelCleanup.removeWhisperModel()
        let catalogStore = RewriteModelCatalogStore.shared
        let speechSettingsStore = SpeechRecognitionSettingsStore()
        let settingsViewModel = RewriteSettingsViewModel(
            catalogStore: catalogStore, speechSettingsStore: speechSettingsStore)
        let store = settingsViewModel.settingsStore
        let dependencies = StetMobileComposition.makeDependencies(
            settingsStore: store,
            speechSettingsStore: speechSettingsStore
        )
        let dictationViewModel = SenseVoiceViewModel(
            coordinator: dependencies.dictationCoordinator,
            liveActivityManager: MicrophoneLiveActivityManager()
        )
        settingsViewModel.onSpeechAssetBecameReady = { [weak dictationViewModel] in
            dictationViewModel?.ensureMicAlive()
        }
        settingsViewModel.onMicrophoneKeepAliveChanged = { [weak dictationViewModel] duration in
            dictationViewModel?.updateMicrophoneKeepAlive(duration)
        }
        _rewriteSettingsStore = StateObject(wrappedValue: store)
        _speechSettingsStore = StateObject(wrappedValue: speechSettingsStore)
        _rewriteSettingsViewModel = StateObject(wrappedValue: settingsViewModel)
        _viewModel = StateObject(wrappedValue: dictationViewModel)
        _appViewModel = StateObject(wrappedValue: AppViewModel(dictationViewModel: dictationViewModel))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                appViewModel: appViewModel,
                viewModel: viewModel,
                rewriteSettingsViewModel: rewriteSettingsViewModel
            )
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                viewModel.ensureMicAlive()
                rewriteSettingsViewModel.refreshSyncedAPIKey()
                Task {
                    await rewriteSettingsViewModel.refreshSpeechAssetStatus()
                }
            }
        }
    }
}

@MainActor
private enum StetMobileComposition {
    struct Dependencies {
        let dictationCoordinator: any DictationSessionCoordinating
    }

    static func makeDependencies(
        settingsStore: RewriteSettingsStore,
        speechSettingsStore: SpeechRecognitionSettingsStore
    ) -> Dependencies {
        let sessionStore = SharedDictationManager.shared
        let audioCapture = PersistentASRAudioCapture(strategy: .builtInPreferred)
        let engine = AppleSpeechDictationEngine(
            settingsStore: speechSettingsStore,
            audioCapture: audioCapture
        )
        engine.onVolumeUpdate = { level in
            SharedDictationManager.shared.updateVolume(level)
        }
        let coordinator = DictationSessionCoordinator(
            engine: engine,
            permissionProvider: SystemMicrophonePermissionProvider(),
            sessionStore: sessionStore,
            postProcessor: SettingsTranscriptPostProcessor(settingsStore: settingsStore),
            commandMonitor: SharedKeyboardCommandMonitor(sessionStore: sessionStore),
            idleStandbyTimeout: speechSettingsStore.microphoneKeepAliveDuration.timeoutDuration,
            activityRecorder: SyncedDictationActivityRecorder()
        )
        return Dependencies(dictationCoordinator: coordinator)
    }
}
