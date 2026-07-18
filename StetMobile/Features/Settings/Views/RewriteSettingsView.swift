import StetAI
import StetCore
import SwiftUI

struct RewriteSettingsView: View {
    @ObservedObject var viewModel: RewriteSettingsViewModel

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(
                        "Engine",
                        selection: $viewModel.dictationSettingsStore.selectedModel
                    ) {
                        ForEach(viewModel.availableDictationModels) { model in
                            Text(model.displayName).tag(model)
                        }
                    }
                    .onChange(of: viewModel.dictationSettingsStore.selectedModel) {
                        viewModel.onDictationModelSelected()
                    }

                    ForEach(viewModel.availableDictationModels) { model in
                        localModelRow(model)
                    }
                } header: {
                    Text("On-Device Dictation")
                } footer: {
                    Text("Choose the active engine and manage each model independently.")
                }

                Section {
                    Toggle("Transcript Improvement", isOn: $viewModel.settingsStore.isRewriteEnabled)
                } footer: {
                    Text("When enabled, transcripts are cleaned up by AI before display.")
                }

                Section("Service") {
                    Picker("Provider", selection: $viewModel.settingsStore.selectedProvider) {
                        ForEach(viewModel.availableProviders) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                    .onChange(of: viewModel.settingsStore.selectedProvider) {
                        viewModel.onProviderChanged()
                    }

                    Picker("Model", selection: $viewModel.settingsStore.selectedModel) {
                        ForEach(RewriteModel.availableModels(for: viewModel.settingsStore.selectedProvider)) { model in
                            Text(model.displayName).tag(model)
                        }
                    }
                }

                Section("API Key") {
                    SecureField("Enter API key", text: $viewModel.apiKeyInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit { viewModel.saveAPIKey() }

                    Button {
                        Task { await viewModel.validateCredential() }
                    } label: {
                        HStack {
                            Text("Validate")
                            Spacer()
                            switch viewModel.validationState {
                            case .idle:
                                EmptyView()
                            case .validating:
                                ProgressView()
                            case .success:
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            case .failed:
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                    .disabled(viewModel.validationState == .validating)

                    if case .failed(let message) = viewModel.validationState {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .task {
                await viewModel.refreshLocalModelStatuses()
            }
        }
    }

    @ViewBuilder
    private func localModelRow(_ model: MobileDictationModel) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                localModelSummary(model)
                Spacer(minLength: 8)
                localModelAction(model)
            }

            VStack(alignment: .leading, spacing: 12) {
                localModelSummary(model)
                localModelAction(model)
            }
        }
        .buttonStyle(.borderless)
    }

    @ViewBuilder
    private func localModelSummary(_ model: MobileDictationModel) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(model.displayName)
            localModelStatus(model)
        }
    }

    @ViewBuilder
    private func localModelStatus(_ model: MobileDictationModel) -> some View {
        switch viewModel.localModelState(for: model) {
        case .checking:
            statusProgress("Checking…")
        case .notDownloaded:
            Text("Not Downloaded")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .downloading:
            statusProgress("Downloading…")
        case .downloaded:
            Label("Downloaded", systemImage: "checkmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(.green)
        case .deleting:
            statusProgress("Deleting…")
        case .downloadFailed:
            Text("Download Failed")
                .font(.footnote)
                .foregroundStyle(.red)
        case .deletionFailed:
            Text("Delete Failed")
                .font(.footnote)
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private func localModelAction(_ model: MobileDictationModel) -> some View {
        switch viewModel.localModelState(for: model) {
        case .notDownloaded:
            Button("Download") {
                Task { await viewModel.downloadLocalModel(model) }
            }
        case .downloadFailed:
            Button("Try Again") {
                Task { await viewModel.downloadLocalModel(model) }
            }
        case .downloaded:
            Button("Delete", role: .destructive) {
                Task { await viewModel.deleteLocalModel(model) }
            }
        case .deletionFailed:
            Button("Try Again", role: .destructive) {
                Task { await viewModel.deleteLocalModel(model) }
            }
        case .checking, .downloading, .deleting:
            EmptyView()
        }
    }

    private func statusProgress(_ title: String) -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(title)
                .foregroundStyle(.secondary)
        }
        .font(.footnote)
    }
}
