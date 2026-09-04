import SwiftUI

@main
struct StetMobileApp: App {
    @StateObject private var rewriteSettingsStore: RewriteSettingsStore
    @StateObject private var funASRSettingsStore: FunASRSettingsStore
    @StateObject private var rewriteSettingsViewModel: RewriteSettingsViewModel
    @StateObject private var appViewModel: AppViewModel
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var viewModel: SenseVoiceViewModel

    init() {
        RetiredDictationModelCleanup.removeWhisperModel()
        let store = RewriteSettingsStore()
        let funASRSettingsStore = FunASRSettingsStore()
        let dependencies = StetMobileComposition.makeDependencies(
            settingsStore: store,
            funASRSettingsStore: funASRSettingsStore
        )
        let dictationViewModel = SenseVoiceViewModel(
            coordinator: dependencies.dictationCoordinator,
            liveActivityManager: MicrophoneLiveActivityManager()
        )
        _rewriteSettingsStore = StateObject(wrappedValue: store)
        _funASRSettingsStore = StateObject(wrappedValue: funASRSettingsStore)
        _rewriteSettingsViewModel = StateObject(
            wrappedValue: RewriteSettingsViewModel(
                settingsStore: store,
                funASRSettingsStore: funASRSettingsStore
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
        funASRSettingsStore: FunASRSettingsStore
    ) -> Dependencies {
        let sessionStore = SharedDictationManager.shared
        let audioCapture = PersistentASRAudioCapture(strategy: .builtInPreferred)
        let engine = FunASRRealtimeEngine(
            configurationProvider: {
                try funASRSettingsStore.configuration()
            },
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
            commandMonitor: SharedKeyboardCommandMonitor(sessionStore: sessionStore)
        )
        return Dependencies(dictationCoordinator: coordinator)
    }
}
