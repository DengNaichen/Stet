import SwiftUI

/// View for testing microphone functionality
struct MicrophoneTestView: View {
    @ObservedObject var viewModel: MicrophoneTestViewModel

    var body: some View {
        VStack(spacing: 16) {
            // Audio level indicator
            MicrophoneAudioLevelMeter(level: viewModel.audioLevel)
                .frame(height: 40)
                .padding(.horizontal, 8)

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
                .buttonStyle(.borderedProminent)
                .tint(viewModel.isRecording ? .red : .accentColor)
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
            if viewModel.hasRecording {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Recording saved - click Play to hear it")
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
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
