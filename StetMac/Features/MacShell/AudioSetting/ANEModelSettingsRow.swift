import SwiftUI
import UniformTypeIdentifiers

struct ANEModelSettingsRow: View {
    @ObservedObject var viewModel: ANEModelSettingsViewModel
    @State private var showsImporter = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Fun-ASR Nano acceleration")
                        .font(MacUI.LinearTypography.rowTitle)
                        .foregroundStyle(MacUI.Foreground.primary)
                    Text(viewModel.statusText)
                        .font(MacUI.LinearTypography.rowSubtitle)
                        .foregroundStyle(MacUI.Foreground.secondary)
                }

                Spacer()

                if viewModel.isBusy {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Button("Cancel") { viewModel.cancel() }
                            .buttonStyle(.bordered)
                            .disabled(viewModel.isCancelling)
                    }
                } else if viewModel.status.supported {
                    if viewModel.status.ready {
                        Button("Use CPU") { viewModel.disable() }
                            .buttonStyle(.bordered)
                    } else {
                        HStack(spacing: 8) {
                            if viewModel.status.canPrepareInstalled {
                                Button("Enable acceleration") { viewModel.prepareInstalled() }
                                    .buttonStyle(.bordered)
                            }
                            if viewModel.status.downloadAvailable {
                                Button("Download") { viewModel.download() }
                                    .buttonStyle(.bordered)
                            }
                            Button("Import model…") { showsImporter = true }
                                .buttonStyle(.bordered)
                        }
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
                .font(MacUI.LinearTypography.rowSubtitle)
                .foregroundStyle(MacUI.LinearSurfaces.mutedInk)
            }

            if let message = viewModel.errorMessage {
                Text(message)
                    .font(MacUI.LinearTypography.rowSubtitle)
                    .foregroundStyle(MacUI.Foreground.error)
            }
        }
        .padding(.horizontal, MacUI.LinearMetrics.rowHorizontalPadding)
        .padding(.vertical, 10)
        .fileImporter(isPresented: $showsImporter, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { viewModel.importCandidate(at: url) }
        }
        .task { await viewModel.refresh() }
    }
}
