import SwiftUI

struct ContentView: View {
    @ObservedObject var appViewModel: AppViewModel
    @ObservedObject var viewModel: SenseVoiceViewModel
    @ObservedObject var rewriteSettingsViewModel: RewriteSettingsViewModel

    var body: some View {
        Group {
            if appViewModel.externalDictationFlow == .capturing {
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
            } else {
                TabView(selection: $appViewModel.selectedTab) {
                    DictionaryView()
                        .tabItem {
                            Label("Dictionary", systemImage: "book.closed.fill")
                        }
                        .tag(AppViewModel.Tab.dictionary)

                    SenseVoiceView(viewModel: viewModel)
                        .tabItem {
                            Label("Dictation", systemImage: "mic.fill")
                        }
                        .tag(AppViewModel.Tab.dictation)

                    RewriteSettingsView(viewModel: rewriteSettingsViewModel)
                        .tabItem {
                            Label("Settings", systemImage: "gearshape.fill")
                        }
                        .tag(AppViewModel.Tab.settings)
                }
            }
        }
        .onOpenURL { url in
            _ = appViewModel.handleIncomingURL(url)
        }
        .fullScreenCover(
            isPresented: Binding(
                get: { appViewModel.externalDictationFlow == .returnGuide },
                set: { isPresented in
                    if !isPresented {
                        appViewModel.dismissExternalGuide()
                    }
                }
            )
        ) {
            ExternalReturnGuideView {
                appViewModel.dismissExternalGuide()
            }
        }
        .task {
            viewModel.start()
        }
    }

    private var statusText: String {
        switch viewModel.state {
        case .idle: return viewModel.partialStatus
        case .loading: return viewModel.partialStatus
        case .starting: return viewModel.partialStatus
        case .recording: return viewModel.partialStatus
        case .processing, .rewriting: return viewModel.partialStatus
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

#if DEBUG
    #Preview {
        let store = RewriteSettingsStore()
        let coordinator = PreviewDictationSessionCoordinator()
        let dictationViewModel = SenseVoiceViewModel(coordinator: coordinator)
        ContentView(
            appViewModel: AppViewModel(dictationViewModel: dictationViewModel),
            viewModel: dictationViewModel,
            rewriteSettingsViewModel: RewriteSettingsViewModel(
                settingsStore: store
            )
        )
    }

    @MainActor
    private final class PreviewDictationSessionCoordinator: DictationSessionCoordinating {
        let events: AsyncStream<DictationCoordinatorEvent>
        private(set) var phase: DictationCoordinatorPhase = .idle

        private let continuation: AsyncStream<DictationCoordinatorEvent>.Continuation

        init() {
            (events, continuation) = AsyncStream.makeStream()
        }

        func start() {
            continuation.yield(.ready(engineName: "FunASR Realtime Preview"))
        }

        func recoverAudioSession() {}
        func synchronizeKeyboardCommands() {}
        func startRecording(sessionId _: String) {}
        func stopRecording(sessionId _: String?) {}
        func cancelRecording(sessionId _: String) {}
        func shutdown() {}
        func shutdown() async {
            continuation.finish()
        }
    }
#endif
