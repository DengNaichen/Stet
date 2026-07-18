import SwiftUI

@main
struct StetMobileApp: App {
    @StateObject private var rewriteSettingsStore: RewriteSettingsStore
    @StateObject private var localDictationSettingsStore: LocalDictationSettingsStore
    @StateObject private var rewriteSettingsViewModel: RewriteSettingsViewModel
    @StateObject private var appViewModel: AppViewModel
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var viewModel: SenseVoiceViewModel

    init() {
        let store = RewriteSettingsStore()
        let dictationSettingsStore = LocalDictationSettingsStore()
        let dependencies = StetMobileComposition.makeDependencies(
            settingsStore: store,
            selectedDictationModel: dictationSettingsStore.selectedModel
        )
        let dictationViewModel = SenseVoiceViewModel(
            coordinator: dependencies.dictationCoordinator,
            liveActivityManager: MicrophoneLiveActivityManager()
        )
        _rewriteSettingsStore = StateObject(wrappedValue: store)
        _localDictationSettingsStore = StateObject(wrappedValue: dictationSettingsStore)
        _rewriteSettingsViewModel = StateObject(
            wrappedValue: RewriteSettingsViewModel(
                settingsStore: store,
                dictationSettingsStore: dictationSettingsStore,
                localModelManagers: dependencies.localModelManagers,
                onLocalModelReady: { model in
                    if dictationSettingsStore.selectedModel == model {
                        dictationViewModel.ensureMicAlive()
                    }
                },
                onLocalModelSelected: { model in
                    dependencies.selectDictationModel(model)
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
        let localModelManagers: [MobileDictationModel: any LocalDictationModelManaging]
        let selectDictationModel: @MainActor (MobileDictationModel) -> Void
    }

    static func makeDependencies(
        settingsStore: RewriteSettingsStore,
        selectedDictationModel: MobileDictationModel
    ) -> Dependencies {
        do {
            let senseVoiceModelManager = try SenseVoiceModelManager()
            let whisperModelManager = try WhisperModelManager()
            let sessionStore = SharedDictationManager.shared
            let coordinator = SelectableDictationSessionCoordinator(
                selectedModel: selectedDictationModel
            ) { model in
                let engine: any ASREngine
                let modelManager: any ASRModelManager
                let modelName: String

                switch model {
                case .senseVoice:
                    let senseVoiceEngine = SherpaOnnxASREngine(modelManager: senseVoiceModelManager)
                    senseVoiceEngine.onVolumeUpdate = { level in
                        SharedDictationManager.shared.updateVolume(level)
                    }
                    engine = senseVoiceEngine
                    modelManager = senseVoiceModelManager
                    modelName = SenseVoiceModelManager.modelName
                case .whisperLargeV3Turbo:
                    let whisperEngine = WhisperASREngine(modelManager: whisperModelManager)
                    whisperEngine.onVolumeUpdate = { level in
                        SharedDictationManager.shared.updateVolume(level)
                    }
                    engine = whisperEngine
                    modelManager = whisperModelManager
                    modelName = WhisperModelManager.modelName
                }

                return DictationSessionCoordinator(
                    engine: engine,
                    modelManager: modelManager,
                    modelName: modelName,
                    permissionProvider: SystemMicrophonePermissionProvider(),
                    sessionStore: sessionStore,
                    postProcessor: SettingsTranscriptPostProcessor(settingsStore: settingsStore),
                    commandMonitor: SharedKeyboardCommandMonitor(sessionStore: sessionStore)
                )
            }

            return Dependencies(
                dictationCoordinator: coordinator,
                localModelManagers: [
                    .senseVoice: SenseVoiceLocalDictationModelManager(
                        modelManager: senseVoiceModelManager
                    ),
                    .whisperLargeV3Turbo: WhisperLocalDictationModelManager(
                        modelManager: whisperModelManager
                    ),
                ],
                selectDictationModel: { model in
                    coordinator.selectModel(model)
                }
            )
        } catch {
            let unavailable = UnavailableLocalDictationModelManager(
                currentStatus: .error(message: error.localizedDescription)
            )
            return Dependencies(
                dictationCoordinator: UnavailableDictationSessionCoordinator(
                    message: error.localizedDescription
                ),
                localModelManagers: [
                    .senseVoice: unavailable,
                    .whisperLargeV3Turbo: unavailable,
                ],
                selectDictationModel: { _ in }
            )
        }
    }
}
