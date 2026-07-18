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
        let coordinator = StetMobileComposition.makeDictationCoordinator(settingsStore: store)
        let dictationViewModel = SenseVoiceViewModel(coordinator: coordinator)
        _rewriteSettingsStore = StateObject(wrappedValue: store)
        _rewriteSettingsViewModel = StateObject(wrappedValue: RewriteSettingsViewModel(settingsStore: store))
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
    static func makeDictationCoordinator(
        settingsStore: RewriteSettingsStore
    ) -> any DictationSessionCoordinating {
        do {
            let modelManager = try SenseVoiceModelManager()
            let engine = SherpaOnnxASREngine(modelManager: modelManager)
            engine.onVolumeUpdate = { level in
                SharedDictationManager.shared.updateVolume(level)
            }

            let sessionStore = SharedDictationManager.shared
            return DictationSessionCoordinator(
                engine: engine,
                modelManager: modelManager,
                permissionProvider: SystemMicrophonePermissionProvider(),
                sessionStore: sessionStore,
                postProcessor: SettingsTranscriptPostProcessor(settingsStore: settingsStore),
                commandMonitor: SharedKeyboardCommandMonitor(sessionStore: sessionStore)
            )
        } catch {
            return UnavailableDictationSessionCoordinator(message: error.localizedDescription)
        }
    }
}
