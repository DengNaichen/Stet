import SwiftUI
import UniformTypeIdentifiers

struct ANEModelSettingsRow: View {
    @ObservedObject var viewModel: ANEModelSettingsViewModel
    @State private var showsImporter = false

    var body: some View {
        VStack(alignment: .leading, spacing: MacUI.SettingsViewMetrics.detailSpacing) {
            HStack {
                VStack(alignment: .leading, spacing: MacUI.SettingsViewMetrics.compactDetailSpacing) {
                    Text("Fun-ASR Nano acceleration")
                        .font(MacUI.Typography.itemTitle)
                    Text(viewModel.statusText)
                        .font(MacUI.Typography.detail)
                        .foregroundStyle(MacUI.Foreground.secondary)
                }
                Spacer()
                if viewModel.isBusy {
                    ProgressView().controlSize(.small)
                    Button("Cancel") { viewModel.cancel() }
                        .disabled(viewModel.isCancelling)
                } else if viewModel.status.supported {
                    if viewModel.status.ready {
                        Button("Use CPU") { viewModel.disable() }
                    } else {
                        if viewModel.status.canPrepareInstalled {
                            Button("Enable acceleration") { viewModel.prepareInstalled() }
                        }
                        if viewModel.status.downloadAvailable {
                            Button("Download") { viewModel.download() }
                        }
                        Button("Import model…") { showsImporter = true }
                    }
                }
            }
            if case .copying(let fraction) = viewModel.phase {
                ProgressView(value: fraction)
            }
            if viewModel.status.supported, !viewModel.status.ready {
                Text(
                    "First-time preparation may take several minutes. CPU transcription remains available while the model is prepared."
                )
                .font(MacUI.Typography.footnote)
                .foregroundStyle(MacUI.Foreground.secondary)
            }
            if let message = viewModel.errorMessage {
                Text(message)
                    .font(MacUI.Typography.footnote)
                    .foregroundStyle(MacUI.Foreground.error)
            }
        }
        .fileImporter(isPresented: $showsImporter, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { viewModel.importCandidate(at: url) }
        }
        .task { await viewModel.refresh() }
    }
}
