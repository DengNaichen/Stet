import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = SenseVoiceViewModel()
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(0)

            HistoryView()
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
                .tag(1)

            DictionaryView()
                .tabItem {
                    Label("Dictionary", systemImage: "book.closed.fill")
                }
                .tag(2)

            SenseVoiceView(viewModel: viewModel)
                .tabItem {
                    Label("Dictate", systemImage: "mic.fill")
                }
                .tag(3)
        }
    }
}

#Preview {
    ContentView()
}
