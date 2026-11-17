import SwiftUI

/// View for testing microphone functionality
struct MicrophoneTestView: View {
    @ObservedObject var viewModel: MicrophoneTestViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: MacUI.SettingsViewMetrics.cardContentSpacing) {
            HStack {
                Label("Test your microphone", systemImage: "mic")
                    .font(MacUI.Typography.emphasizedFieldLabel)
                Spacer()
                Group {
                    if viewModel.isRecording {
                        Text("Recording")
                    } else if viewModel.isPlaying {
                        Text("Playing")
                    } else {
                        Text("Ready")
                    }
                }
                .font(MacUI.Typography.caption).foregroundStyle(MacUI.Foreground.secondary)
            }
            // Audio level indicator
            MicrophoneAudioLevelMeter(level: viewModel.audioLevel)

            // Recording controls
            HStack(spacing: MacUI.SettingsViewMetrics.rowContentSpacing) {
                Button {
                    Task {
                        if viewModel.isRecording {
                            await viewModel.stopRecording()
                        } else {
                            await viewModel.startRecording()
                        }
                    }
                } label: {
                    let recordTitle: LocalizedStringKey = viewModel.isRecording ? "Stop Recording" : "Start Recording"
                    Label(
                        recordTitle,
                        systemImage: viewModel.isRecording ? "stop.circle.fill" : "record.circle"
                    )
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isPlaying)

                // Playback controls
                Button {
                    Task {
                        if viewModel.isPlaying {
                            viewModel.stopPlayback()
                        } else {
                            await viewModel.playRecording()
                        }
                    }
                } label: {
                    let playbackTitle: LocalizedStringKey = viewModel.isPlaying ? "Stop Playback" : "Play Recording"
                    Label(
                        playbackTitle,
                        systemImage: viewModel.isPlaying ? "stop.circle.fill" : "play.circle"
                    )
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.hasRecording || viewModel.isRecording)
            }

            // Status text
            if viewModel.hasRecording && !viewModel.isRecording {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(MacUI.Foreground.secondary)
                    Text("Play back your test to check the sound.")
                        .font(MacUI.Typography.caption)
                        .foregroundStyle(MacUI.Foreground.secondary)
                }
            } else if viewModel.isRecording {
                HStack {
                    ProgressView()
                        .scaleEffect(MacUI.SettingsViewMetrics.compactProgressScale)
                    Text("Recording...")
                        .font(MacUI.Typography.caption)
                        .foregroundStyle(MacUI.Foreground.secondary)
                }
            } else {
                Text("Record a short phrase, then play it back to check your input.")
                    .font(MacUI.Typography.caption).foregroundStyle(MacUI.Foreground.secondary)
            }
        }
        .padding(.vertical, MacUI.SettingsViewMetrics.microphoneTestVerticalPadding)
    }
}
