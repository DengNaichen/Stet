import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: SenseVoiceViewModel
    @ObservedObject var rewriteSettingsViewModel: RewriteSettingsViewModel
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
                    DictionaryView()
                        .tabItem {
                            Label("Dictionary", systemImage: "book.closed.fill")
                        }
                        .tag(0)

                    SenseVoiceView(viewModel: viewModel)
                        .tabItem {
                            Label("Dictate", systemImage: "mic.fill")
                        }
                        .tag(1)

                    RewriteSettingsView(viewModel: rewriteSettingsViewModel)
                        .tabItem {
                            Label("Settings", systemImage: "gearshape.fill")
                        }
                        .tag(2)
                }
                .onOpenURL { url in
                    guard viewModel.handleIncomingURL(url) else { return }
                    selectedTab = 1
                }
            }
        }
    }

    private var statusText: String {
        switch viewModel.state {
        case .idle: return viewModel.partialStatus
        case .loading: return "Loading model..."
        case .recording: return viewModel.partialStatus
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
    return ContentView(
        viewModel: SenseVoiceViewModel(rewriteSettingsStore: store),
        rewriteSettingsViewModel: RewriteSettingsViewModel(settingsStore: store)
    )
}
