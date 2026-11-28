import SwiftUI

@main
struct StetMobileApp: App {
    @StateObject private var rewriteSettingsStore: RewriteSettingsStore
    @StateObject private var speechRecognitionSettingsStore: SpeechRecognitionSettingsStore
    @StateObject private var rewriteSettingsViewModel: RewriteSettingsViewModel
    @StateObject private var appViewModel: AppViewModel
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var viewModel: SenseVoiceViewModel

    init() {
        RetiredDictationModelCleanup.removeWhisperModel()
        let store = RewriteSettingsStore()
        let speechRecognitionSettingsStore = SpeechRecognitionSettingsStore()
        let dependencies = StetMobileComposition.makeDependencies(
            settingsStore: store,
            speechRecognitionSettingsStore: speechRecognitionSettingsStore
        )
        let dictationViewModel = SenseVoiceViewModel(
            coordinator: dependencies.dictationCoordinator,
            liveActivityManager: MicrophoneLiveActivityManager()
        )
        _rewriteSettingsStore = StateObject(wrappedValue: store)
        _speechRecognitionSettingsStore = StateObject(wrappedValue: speechRecognitionSettingsStore)
        _rewriteSettingsViewModel = StateObject(
            wrappedValue: RewriteSettingsViewModel(
                settingsStore: store,
                speechRecognitionSettingsStore: speechRecognitionSettingsStore
            )
        )
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
        .onChange(of: speechRecognitionSettingsStore.assetStatus.isReady) { _, isReady in
            if isReady {
                viewModel.ensureMicAlive()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                viewModel.ensureMicAlive()
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
        speechRecognitionSettingsStore: SpeechRecognitionSettingsStore
    ) -> Dependencies {
        let sessionStore = SharedDictationManager.shared
        let engine = AppleSpeechDictationEngine(settingsStore: speechRecognitionSettingsStore)
        engine.onVolumeUpdate = { level in
            SharedDictationManager.shared.updateVolume(level)
        }
        let coordinator = DictationSessionCoordinator(
            engine: engine,
            permissionProvider: SystemMicrophonePermissionProvider(),
            sessionStore: sessionStore,
            postProcessor: SettingsTranscriptPostProcessor(settingsStore: settingsStore),
            commandMonitor: SharedKeyboardCommandMonitor(sessionStore: sessionStore)
        )
        return Dependencies(dictationCoordinator: coordinator)
    }
}
