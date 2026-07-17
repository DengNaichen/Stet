import SwiftUI

struct SenseVoiceView: View {
    @ObservedObject var viewModel: SenseVoiceViewModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Text("SenseVoice")
                        .font(.largeTitle.bold())
                    Text(viewModel.activeEngineName.isEmpty ? "Ready to dictate" : "Powered by \(viewModel.activeEngineName)")
                        .foregroundStyle(.secondary)

                    Picker("ASR Engine", selection: $viewModel.selectedEngineType) {
                        ForEach(ASREngineType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.top, 4)
                    .disabled(viewModel.isRecording)
                }

                ScrollView {
                    Text(viewModel.transcript.isEmpty ? "Transcript will appear here after recording stops." : viewModel.transcript)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                VStack(alignment: .leading, spacing: 8) {
                    Text(statusText)
                        .foregroundStyle(statusColor)
                    
                    if !viewModel.activeEngineName.isEmpty {
                        Text("Active Backend: \(viewModel.activeEngineName)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
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
            .navigationTitle("Dictation")
            .fullScreenCover(isPresented: $viewModel.isExternalLaunch) {
                ExternalReturnGuideView {
                    viewModel.dismissExternalGuide()
                }
            }
        }
    }

    private var statusText: String {
        switch viewModel.state {
        case .idle:
            return viewModel.partialStatus
        case .loading:
            return "Loading model..."
        case .recording:
            return viewModel.partialStatus
        case .warming:
            return "Warming up SenseVoice..."
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
