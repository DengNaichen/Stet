import SwiftUI
#if os(iOS)
    import StetVisuals
#endif

struct DictationView: View {
    @StateObject private var viewModel: DictationViewModel

    init(speechService: any SpeechService = ConfigurableSpeechService.live()) {
        _viewModel = StateObject(wrappedValue: DictationViewModel(speechService: speechService))
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 8) {
                Text("Stet")
                    .font(.title)
                    .fontWeight(.semibold)

                Text(viewModel.state.statusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            primaryControl

            messageView
                .frame(maxWidth: .infinity, minHeight: 80)
                .padding()
                .background(messageBackgroundColor)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            if showsReset {
                Button("Reset") {
                    viewModel.send(.resetTapped)
                }
                .buttonStyle(.bordered)
            }

            Spacer()
        }
        .padding(24)
    }

    private var messageBackgroundColor: Color {
        #if os(macOS)
            return Color(nsColor: .controlBackgroundColor)
        #else
            return Color(.secondarySystemBackground)
        #endif
    }

    @ViewBuilder
    private var primaryControl: some View {
        #if os(iOS)
            if usesListeningShader {
                Button(action: stopListeningFromShader) {
                    DictationLevelShaderView(
                        level: viewModel.recordingLevel,
                        diameter: 120,
                        preferredFramesPerSecond: 40,
                        isPaused: isListeningShaderPaused
                    )
                }
                .buttonStyle(DictationShaderButtonStyle())
                .contentShape(Circle())
                .disabled(isListeningShaderPaused)
                .accessibilityLabel("停止录音")
            } else {
                legacyPrimaryControl
            }
        #else
            legacyPrimaryControl
        #endif
    }

    private var legacyPrimaryControl: some View {
        ZStack {
            Circle()
                .fill(buttonColor)
                .frame(width: 120, height: 120)

            Text(primaryButtonLabel)
                .font(.headline)
                .foregroundStyle(.white)
        }
        .onTapGesture {
            viewModel.send(primaryAction)
        }
    }

    #if os(iOS)
        private var usesListeningShader: Bool {
            switch viewModel.state {
            case .listening, .processing:
                return true
            case .idle, .starting, .result, .clipboardPending, .error:
                return false
            }
        }

        private var isListeningShaderPaused: Bool {
            if case .processing = viewModel.state {
                return true
            }
            return false
        }

        private func stopListeningFromShader() {
            guard case .listening = viewModel.state else { return }
            viewModel.send(.stopTapped)
        }
    #endif

    private var primaryAction: DictationAction {
        switch viewModel.state {
        case .idle:
            return .startTapped
        case .starting:
            return .resetTapped
        case .listening:
            return .stopTapped
        case .processing:
            return .resetTapped
        case .result, .error:
            return .startTapped
        case .clipboardPending:
            return .resetTapped
        }
    }

    private var primaryButtonLabel: String {
        switch viewModel.state {
        case .idle:
            return "Start"
        case .starting:
            return "Cancel"
        case .listening:
            return "Stop"
        case .processing:
            return "Wait"
        case .result, .error:
            return "Again"
        case .clipboardPending:
            return "Dismiss"
        }
    }

    private var buttonColor: Color {
        switch viewModel.state {
        case .idle:
            return .blue
        case .starting:
            return .orange
        case .listening:
            return .red
        case .processing:
            return .orange
        case .result:
            return .green
        case .clipboardPending:
            return .mint
        case .error:
            return .gray
        }
    }

    private var showsReset: Bool {
        switch viewModel.state {
        case .idle, .starting, .listening, .processing, .result, .clipboardPending, .error:
            return false
        }
    }

    @ViewBuilder
    private var messageView: some View {
        switch viewModel.state {
        case .idle:
            Text("Tap Start to begin dictation.")
                .foregroundStyle(.secondary)

        case .starting:
            ProgressView("Starting microphone...")

        case .listening:
            Text("Speak naturally, then tap Stop when you are ready to finalize the transcript.")
                .foregroundStyle(.secondary)

        case .processing:
            ProgressView("Finalizing transcription...")

        case .result(let text):
            Text(text)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .clipboardPending(let text):
            Text(text)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .error(let failure):
            Text(failure.message)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#if os(iOS)
    private struct DictationShaderButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
        }
    }
#endif

struct DictationView_Previews: PreviewProvider {
    static var previews: some View {
        DictationView(speechService: MockSpeechService())
    }
}
