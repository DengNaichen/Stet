import SwiftUI

struct SenseVoiceView: View {
    @ObservedObject var viewModel: SenseVoiceViewModel

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
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .navigationTitle("Dictation")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if !viewModel.transcript.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Clear", action: viewModel.clearTranscript)
                    }
                }
            }
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
}
