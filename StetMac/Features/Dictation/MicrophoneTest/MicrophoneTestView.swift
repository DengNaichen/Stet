import SwiftUI

/// View for testing microphone functionality
struct MicrophoneTestView: View {
    @ObservedObject var viewModel: MicrophoneTestViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Test your microphone", systemImage: "mic")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(viewModel.isRecording ? "Recording" : viewModel.isPlaying ? "Playing" : "Ready")
                    .font(.caption).foregroundStyle(.secondary)
            }
            // Audio level indicator
            MicrophoneAudioLevelMeter(level: viewModel.audioLevel)

            // Recording controls
            HStack(spacing: 12) {
                Button {
                    Task {
                        if viewModel.isRecording {
                            await viewModel.stopRecording()
                        } else {
                            await viewModel.startRecording()
                        }
                    }
                } label: {
                    Label(
                        viewModel.isRecording ? "Stop Recording" : "Start Recording",
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
                    Label(
                        viewModel.isPlaying ? "Stop Playback" : "Play Recording",
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
                        .foregroundStyle(.secondary)
                    Text("Play back your test to check the sound.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if viewModel.isRecording {
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Recording...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Record a short phrase, then play it back to check your input.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
    }
}
