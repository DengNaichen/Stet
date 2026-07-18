import SwiftUI

@main
struct StetMobileApp: App {
    @StateObject private var rewriteSettingsStore: RewriteSettingsStore
    @StateObject private var rewriteSettingsViewModel: RewriteSettingsViewModel
    @Environment(\.scenePhase) private var scenePhase

    // SenseVoiceViewModel is initialized lazily because it needs the shared store
    @StateObject private var viewModel: SenseVoiceViewModel

    init() {
        let store = RewriteSettingsStore()
        _rewriteSettingsStore = StateObject(wrappedValue: store)
        _rewriteSettingsViewModel = StateObject(wrappedValue: RewriteSettingsViewModel(settingsStore: store))
        _viewModel = StateObject(wrappedValue: SenseVoiceViewModel(rewriteSettingsStore: store))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel, rewriteSettingsViewModel: rewriteSettingsViewModel)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                viewModel.ensureMicAlive()
            }
        }
    }
}
