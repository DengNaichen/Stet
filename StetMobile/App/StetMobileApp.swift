import SwiftUI

@main
struct StetMobileApp: App {
    @StateObject private var rewriteSettingsStore: RewriteSettingsStore
    @StateObject private var dictationSettingsStore: MobileDictationSettingsStore
    @StateObject private var funASRSettingsStore: FunASRSettingsStore
    @StateObject private var rewriteSettingsViewModel: RewriteSettingsViewModel
    @StateObject private var appViewModel: AppViewModel
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var viewModel: SenseVoiceViewModel

    init() {
        RetiredDictationModelCleanup.removeWhisperModel()
        let store = RewriteSettingsStore()
        let dictationSettingsStore = MobileDictationSettingsStore()
        let funASRSettingsStore = FunASRSettingsStore()
        let dependencies = StetMobileComposition.makeDependencies(
            settingsStore: store,
            funASRSettingsStore: funASRSettingsStore,
            selectedDictationEngine: dictationSettingsStore.selectedEngine
        )
        let dictationViewModel = SenseVoiceViewModel(
            coordinator: dependencies.dictationCoordinator,
            liveActivityManager: MicrophoneLiveActivityManager()
        )
        _rewriteSettingsStore = StateObject(wrappedValue: store)
        _dictationSettingsStore = StateObject(wrappedValue: dictationSettingsStore)
        _funASRSettingsStore = StateObject(wrappedValue: funASRSettingsStore)
        _rewriteSettingsViewModel = StateObject(
            wrappedValue: RewriteSettingsViewModel(
                settingsStore: store,
                dictationSettingsStore: dictationSettingsStore,
                funASRSettingsStore: funASRSettingsStore,
                localModelManagers: dependencies.localModelManagers,
                onLocalModelReady: { engine in
                    if dictationSettingsStore.selectedEngine == engine {
                        dictationViewModel.ensureMicAlive()
                    }
                },
                onDictationEngineSelected: { engine in
                    dependencies.selectDictationEngine(engine)
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
        let localModelManagers: [MobileDictationEngine: any LocalDictationModelManaging]
        let selectDictationEngine: @MainActor (MobileDictationEngine) -> Void
    }

    static func makeDependencies(
        settingsStore: RewriteSettingsStore,
        funASRSettingsStore: FunASRSettingsStore,
        selectedDictationEngine: MobileDictationEngine
    ) -> Dependencies {
        let senseVoiceModelManager = try? SenseVoiceModelManager()
        let sessionStore = SharedDictationManager.shared
        let coordinator = SelectableDictationSessionCoordinator(
            selectedEngine: selectedDictationEngine
        ) { selectedEngine in
            let engine: any ASREngine
            let prepareResources: DictationSessionCoordinator.ResourcePreparation

            switch selectedEngine {
            case .senseVoice:
                guard let senseVoiceModelManager else {
                    return UnavailableDictationSessionCoordinator(
                        message: "SenseVoice is unavailable on this device."
                    )
                }
                let senseVoiceEngine = SherpaOnnxASREngine(modelManager: senseVoiceModelManager)
                senseVoiceEngine.onVolumeUpdate = { level in
                    SharedDictationManager.shared.updateVolume(level)
                }
                engine = senseVoiceEngine
                prepareResources = {
                    try await senseVoiceModelManager.downloadIfNeeded(
                        for: SenseVoiceModelManager.modelName
                    )
                }
            case .funASRRealtime:
                let funASREngine = FunASRRealtimeEngine {
                    try funASRSettingsStore.configuration()
                }
                funASREngine.onVolumeUpdate = { level in
                    SharedDictationManager.shared.updateVolume(level)
                }
                engine = funASREngine
                prepareResources = {}
            }

            return DictationSessionCoordinator(
                engine: engine,
                prepareResources: prepareResources,
                permissionProvider: SystemMicrophonePermissionProvider(),
                sessionStore: sessionStore,
                postProcessor: SettingsTranscriptPostProcessor(settingsStore: settingsStore),
                commandMonitor: SharedKeyboardCommandMonitor(sessionStore: sessionStore)
            )
        }

        let unavailable = UnavailableLocalDictationModelManager(
            currentStatus: .error(message: "This model is unavailable on this device.")
        )
        let senseVoiceLocalManager: any LocalDictationModelManaging =
            senseVoiceModelManager.map {
                SenseVoiceLocalDictationModelManager(modelManager: $0)
            } ?? unavailable
        return Dependencies(
            dictationCoordinator: coordinator,
            localModelManagers: [
                .senseVoice: senseVoiceLocalManager
            ],
            selectDictationEngine: { engine in
                coordinator.selectEngine(engine)
            }
        )
    }
}
