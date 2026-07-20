import SwiftUI

struct SenseVoiceView: View {
    @ObservedObject var viewModel: SenseVoiceViewModel
    @AppStorage(
        MobileDictationVisualTheme.mobileStorageKey,
        store: MobileDictationVisualTheme.mobileDefaults
    ) private var themeRawValue = MobileDictationVisualTheme.egg.rawValue

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    Text(
                        viewModel.transcript.isEmpty
                            ? "Transcript will appear here after recording stops." : viewModel.transcript
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(viewModel.transcript.isEmpty ? Color.secondary : Color.primary)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }

                VStack(spacing: 12) {
                    Text(statusText)
                        .foregroundStyle(statusColor)
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    recordingControl
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .navigationTitle("Dictation")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if !viewModel.transcript.isEmpty {
                        Button("Clear", action: viewModel.clearTranscript)
                    }

                    Picker(selection: themeSelection) {
                        ForEach(MobileDictationVisualTheme.allCases) { theme in
                            Text(theme.title)
                                .tag(theme)
                        }
                    } label: {
                        Label("Theme", systemImage: "paintpalette")
                    }
                    .pickerStyle(.menu)
                }
            }
        }
    }

    @ViewBuilder
    private var recordingControl: some View {
        if usesListeningShader {
            DictationLevelShaderView(
                level: viewModel.recordingLevel,
                diameter: 120,
                preferredFramesPerSecond: 40,
                isPaused: isListeningShaderPaused,
                theme: selectedTheme
            )
            .overlay {
                if viewModel.state == .recording {
                    Button(action: viewModel.toggleRecording) {
                        Color.clear
                            .frame(width: 120, height: 120)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("停止录音")
                }
            }
        } else {
            Button(action: viewModel.toggleRecording) {
                Label(
                    viewModel.isRecording ? "Stop" : "Record",
                    systemImage: viewModel.isRecording ? "stop.fill" : "mic.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!viewModel.canToggleRecording)
        }
    }

    private var usesListeningShader: Bool {
        switch viewModel.state {
        case .recording, .processing, .rewriting:
            true
        case .loading, .idle, .starting, .failed:
            false
        }
    }

    private var isListeningShaderPaused: Bool {
        switch viewModel.state {
        case .processing, .rewriting:
            true
        case .loading, .idle, .starting, .recording, .failed:
            false
        }
    }

    private var statusText: String {
        switch viewModel.state {
        case .idle:
            return viewModel.partialStatus
        case .loading:
            return viewModel.partialStatus
        case .starting:
            return viewModel.partialStatus
        case .recording:
            return viewModel.partialStatus
        case .processing, .rewriting:
            return viewModel.partialStatus
        case .failed(let message):
            return message
        }
    }

    private var statusColor: Color {
        if case .failed = viewModel.state {
            return .red
        }
        return .secondary
    }

    private var selectedTheme: MobileDictationVisualTheme {
        MobileDictationVisualTheme(rawValue: themeRawValue) ?? .egg
    }

    private var themeSelection: Binding<MobileDictationVisualTheme> {
        Binding(
            get: { selectedTheme },
            set: { themeRawValue = $0.rawValue }
        )
    }
}
