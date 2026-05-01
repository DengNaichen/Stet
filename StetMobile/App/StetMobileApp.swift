import SwiftUI

@main
struct StetMobileApp: App {
    @StateObject private var rewriteSettingsStore = RewriteSettingsStore()
    @Environment(\.scenePhase) private var scenePhase

    // SenseVoiceViewModel is initialized lazily because it needs the shared store
    @StateObject private var viewModel: SenseVoiceViewModel

    init() {
        let store = RewriteSettingsStore()
        _rewriteSettingsStore = StateObject(wrappedValue: store)
        _viewModel = StateObject(wrappedValue: SenseVoiceViewModel(rewriteSettingsStore: store))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel, rewriteSettingsStore: rewriteSettingsStore)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                viewModel.ensureMicAlive()
            }
        }
    }
}
