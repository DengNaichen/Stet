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
                        selection: $viewModel.dictationSettingsStore.selectedEngine
                    ) {
                        ForEach(viewModel.availableDictationEngines) { engine in
                            Text(engine.displayName).tag(engine)
                        }
                    }
                    .onChange(of: viewModel.dictationSettingsStore.selectedEngine) {
                        viewModel.onDictationEngineSelected()
                    }
                } header: {
                    Text("Dictation Engine")
                } footer: {
                    Text("FunASR Realtime sends live microphone audio to Alibaba Cloud.")
                }

                if viewModel.dictationSettingsStore.selectedEngine == .funASRRealtime {
                    Section("FunASR Realtime") {
                        Picker("Region", selection: $viewModel.funASRSettingsStore.region) {
                            ForEach(FunASRRegion.allCases) { region in
                                Text(region.displayName).tag(region)
                            }
                        }

                        TextField(
                            "Workspace ID",
                            text: $viewModel.funASRSettingsStore.workspaceID
                        )
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: viewModel.funASRSettingsStore.workspaceID) {
                            viewModel.sanitizeFunASRWorkspaceID()
                        }

                        SecureField("API Key", text: $viewModel.funASRAPIKeyInput)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onSubmit { viewModel.saveFunASRAPIKey() }

                        Button {
                            Task { await viewModel.validateFunASRConnection() }
                        } label: {
                            HStack {
                                Text("Validate Connection")
                                Spacer()
                                validationIndicator(viewModel.funASRValidationState)
                            }
                        }
                        .disabled(viewModel.funASRValidationState == .validating)

                        if case .failed(let message) = viewModel.funASRValidationState {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }

                Section("Local Models") {
                    ForEach(viewModel.availableLocalDictationEngines) { engine in
                        localModelRow(engine)
                    }
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
    private func localModelRow(_ model: MobileDictationEngine) -> some View {
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
    private func localModelSummary(_ model: MobileDictationEngine) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(model.displayName)
            localModelStatus(model)
        }
    }

    @ViewBuilder
    private func localModelStatus(_ model: MobileDictationEngine) -> some View {
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
    private func localModelAction(_ model: MobileDictationEngine) -> some View {
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

    @ViewBuilder
    private func validationIndicator(_ state: RewriteSettingsViewModel.ValidationState) -> some View {
        switch state {
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
