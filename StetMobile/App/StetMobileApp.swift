import SwiftUI

@main
struct StetMobileApp: App {
    @StateObject private var rewriteSettingsStore: RewriteSettingsStore
    @StateObject private var rewriteSettingsViewModel: RewriteSettingsViewModel
    @StateObject private var appViewModel: AppViewModel
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var viewModel: SenseVoiceViewModel

    init() {
        let store = RewriteSettingsStore()
        let dependencies = StetMobileComposition.makeDependencies(settingsStore: store)
        let dictationViewModel = SenseVoiceViewModel(
            coordinator: dependencies.dictationCoordinator,
            liveActivityManager: MicrophoneLiveActivityManager()
        )
        _rewriteSettingsStore = StateObject(wrappedValue: store)
        _rewriteSettingsViewModel = StateObject(
            wrappedValue: RewriteSettingsViewModel(
                settingsStore: store,
                localModelManager: dependencies.localModelManager,
                onLocalModelReady: {
                    dictationViewModel.ensureMicAlive()
                }
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
        let localModelManager: any LocalDictationModelManaging
    }

    static func makeDependencies(
        settingsStore: RewriteSettingsStore
    ) -> Dependencies {
        do {
            let modelManager = try SenseVoiceModelManager()
            let engine = SherpaOnnxASREngine(modelManager: modelManager)
            engine.onVolumeUpdate = { level in
                SharedDictationManager.shared.updateVolume(level)
            }

            let sessionStore = SharedDictationManager.shared
            return Dependencies(
                dictationCoordinator: DictationSessionCoordinator(
                    engine: engine,
                    modelManager: modelManager,
                    permissionProvider: SystemMicrophonePermissionProvider(),
                    sessionStore: sessionStore,
                    postProcessor: SettingsTranscriptPostProcessor(settingsStore: settingsStore),
                    commandMonitor: SharedKeyboardCommandMonitor(sessionStore: sessionStore)
                ),
                localModelManager: SenseVoiceLocalDictationModelManager(modelManager: modelManager)
            )
        } catch {
            return Dependencies(
                dictationCoordinator: UnavailableDictationSessionCoordinator(
                    message: error.localizedDescription
                ),
                localModelManager: UnavailableLocalDictationModelManager(
                    currentStatus: .error(message: error.localizedDescription)
                )
            )
        }
    }
}
