import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: SenseVoiceViewModel
    @ObservedObject var rewriteSettingsStore: RewriteSettingsStore
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(0)

            DictionaryView()
                .tabItem {
                    Label("Dictionary", systemImage: "book.closed.fill")
                }
                .tag(1)

            SenseVoiceView(viewModel: viewModel)
                .tabItem {
                    Label("Dictate", systemImage: "mic.fill")
                }
                .tag(2)

            RewriteSettingsView(viewModel: RewriteSettingsViewModel(settingsStore: rewriteSettingsStore))
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(3)
        }
        .onOpenURL { url in
            guard viewModel.handleIncomingURL(url) else { return }
            selectedTab = 2
        }
    }
}

#Preview {
    let store = RewriteSettingsStore()
    return ContentView(viewModel: SenseVoiceViewModel(rewriteSettingsStore: store), rewriteSettingsStore: store)
}
