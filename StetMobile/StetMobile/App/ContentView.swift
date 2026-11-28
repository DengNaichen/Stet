import SwiftUI

struct ContentView: View {
    @ObservedObject var appViewModel: AppViewModel
    @ObservedObject var viewModel: SenseVoiceViewModel
    @ObservedObject var rewriteSettingsViewModel: RewriteSettingsViewModel

    @AppStorage(
        MobileDictationVisualTheme.mobileStorageKey,
        store: MobileDictationVisualTheme.mobileDefaults
    ) private var themeRawValue = MobileDictationVisualTheme.egg.rawValue

    var body: some View {
        Group {
            if appViewModel.externalDictationFlow == .capturing {
                externalCaptureView
            } else {
                nativeLinearTabView
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

    private var nativeLinearTabView: some View {
        TabView(selection: $appViewModel.selectedTab) {
            Tab(value: AppViewModel.Tab.overview) {
                OverviewView()
                    .tint(nil)
            } label: {
                linearTabIcon("house", label: "Overview")
            }

            Tab(value: AppViewModel.Tab.history) {
                HistoryView()
                    .tint(nil)
            } label: {
                linearTabIcon("clock", label: "History")
            }

            Tab(value: AppViewModel.Tab.dictionary) {
                DictionaryView()
                    .tint(nil)
            } label: {
                linearTabIcon("book.closed", label: "Dictionary")
            }

            Tab(value: AppViewModel.Tab.settings) {
                RewriteSettingsView(viewModel: rewriteSettingsViewModel)
                    .tint(nil)
            } label: {
                linearTabIcon("gearshape", label: "Settings")
            }

            Tab(value: AppViewModel.Tab.dictation, role: dictationTabRole) {
                SenseVoiceView(
                    viewModel: viewModel,
                    languageLabel: rewriteSettingsViewModel.languageSummaryLabel,
                    speechAssetStatus: rewriteSettingsViewModel.speechAssetStatus,
                    isRewriteEnabled: rewriteSettingsViewModel.settingsStore.isRewriteEnabled,
                    onOpenSettings: {
                        appViewModel.selectedTab = .settings
                    }
                )
                .tint(nil)
            } label: {
                linearTabIcon("waveform", label: "Dictation")
            }
        }
        .tint(.primary)
    }

    /// Render a template UIImage so UIKit TabBar never forces `.fill` onto outline SF Symbols.
    private func linearTabIcon(_ systemName: String, label: String) -> some View {
        let config = UIImage.SymbolConfiguration(pointSize: 17, weight: .regular)
        let rendered = UIImage(systemName: systemName, withConfiguration: config)?
            .withRenderingMode(.alwaysTemplate)
        return Group {
            if let rendered {
                Image(uiImage: rendered)
                    .renderingMode(.template)
            } else {
                Image(systemName: systemName)
            }
        }
        .accessibilityLabel(label)
    }

    private var dictationTabRole: TabRole? {
        if #available(iOS 27.0, *) {
            return .prominent
        }
        return nil
    }

    private var externalCaptureView: some View {
        VStack(spacing: 24) {
            HStack {
                Spacer()
                if case .failed = viewModel.state {
                    Button {
                        appViewModel.dismissExternalGuide()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 36, height: 36)
                            .background(Color(.tertiarySystemFill), in: Circle())
                    }
                    .accessibilityLabel("Dismiss")
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            Spacer()

            ZStack {
                Circle()
                    .fill(selectedTheme.accentColor.opacity(0.18))
                    .frame(width: 164, height: 164)
                    .blur(radius: 24)

                if viewModel.isRecording || viewModel.state == .processing || viewModel.state == .rewriting {
                    DictationLevelShaderView(
                        level: viewModel.recordingLevel,
                        diameter: 128,
                        preferredFramesPerSecond: 40,
                        isPaused: viewModel.state == .processing || viewModel.state == .rewriting,
                        theme: selectedTheme
                    )
                    .shadow(color: selectedTheme.accentColor.opacity(0.3), radius: 20, y: 8)
                } else {
                    Image(systemName: isFailed ? "mic.slash.circle.fill" : "mic.circle.fill")
                        .font(.system(size: 84))
                        .foregroundStyle(isFailed ? Color.red : Color.primary)
                        .symbolEffect(.pulse, options: .repeating, isActive: !isFailed)
                }
            }

            VStack(spacing: 8) {
                Text(statusText)
                    .font(.headline)
                    .foregroundStyle(statusColor)
                    .multilineTextAlignment(.center)

                if !viewModel.transcript.isEmpty {
                    Text(viewModel.transcript)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                        .padding(.top, 4)
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }

    private var selectedTheme: MobileDictationVisualTheme {
        MobileDictationVisualTheme(rawValue: themeRawValue) ?? .egg
    }

    private var isFailed: Bool {
        if case .failed = viewModel.state {
            return true
        }
        return false
    }

    private var statusText: String {
        switch viewModel.state {
        case .idle, .loading, .starting, .recording, .processing, .rewriting:
            return viewModel.partialStatus
        case .failed(let message):
            return message
        }
    }

    private var statusColor: Color {
        isFailed ? .red : .primary
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
            continuation.yield(.ready(engineName: "Apple Speech Preview"))
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
