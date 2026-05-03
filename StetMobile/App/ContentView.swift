import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: SenseVoiceViewModel
    @ObservedObject var rewriteSettingsStore: RewriteSettingsStore
    @State private var selectedTab = 0

    var body: some View {
        Group {
            if viewModel.isExternalLaunch && !viewModel.isRecordingDone {
                VStack(spacing: 24) {
                    Spacer()
                    Image(systemName: viewModel.isRecording ? "waveform.circle.fill" : "mic.circle.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(viewModel.isRecording ? Color.red : Color.secondary)
                        .symbolEffect(.pulse, options: .repeating, isActive: viewModel.isRecording)
                    
                    Text(statusText)
                        .font(.headline)
                        .foregroundStyle(statusColor)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(uiColor: .systemBackground))
                .fullScreenCover(isPresented: $viewModel.isExternalLaunch) {
                    ExternalReturnGuideView {
                        viewModel.dismissExternalGuide()
                    }
                }
                .onOpenURL { url in
                    _ = viewModel.handleIncomingURL(url)
                }
            } else {
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
    }

    private var statusText: String {
        switch viewModel.state {
        case .idle: return viewModel.partialStatus
        case .loading: return "Loading model..."
        case .recording: return viewModel.partialStatus
        case .warming: return "Warming up SenseVoice..."
        case .failed(let message): return message
        }
    }

    private var statusColor: Color {
        if case .failed = viewModel.state {
            return .red
        }
        return .secondary
    }
}

#Preview {
    let store = RewriteSettingsStore()
    return ContentView(viewModel: SenseVoiceViewModel(rewriteSettingsStore: store), rewriteSettingsStore: store)
}
