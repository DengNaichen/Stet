import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = SenseVoiceViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Text("SenseVoice")
                        .font(.largeTitle.bold())
                    Text("sherpa-onnx offline ASR demo")
                        .foregroundStyle(.secondary)
                }

                ScrollView {
                    Text(viewModel.transcript.isEmpty ? "Transcript will appear here after VAD emits a speech segment." : viewModel.transcript)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                VStack(alignment: .leading, spacing: 8) {
                    Text(statusText)
                        .foregroundStyle(statusColor)
                    Text(viewModel.metricsText)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 12) {
                    Button(action: viewModel.toggleRecording) {
                        Label(viewModel.isRecording ? "Stop" : "Record", systemImage: viewModel.isRecording ? "stop.fill" : "mic.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button("Clear", action: viewModel.clearTranscript)
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                }
            }
            .padding(24)
            .navigationTitle("testvoice")
        }
    }

    private var statusText: String {
        switch viewModel.state {
        case .idle:
            return viewModel.partialStatus
        case .loading:
            return viewModel.isRecording ? "Loading model..." : "Decoding..."
        case .recording:
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

#Preview {
    ContentView()
}
