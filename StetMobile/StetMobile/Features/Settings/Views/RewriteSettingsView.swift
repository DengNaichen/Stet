import StetAI
import StetCore
import SwiftUI

struct RewriteSettingsView: View {
    @ObservedObject var viewModel: RewriteSettingsViewModel

    var body: some View {
        NavigationStack {
            Form {
                Section {
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
                } header: {
                    Text("FunASR Realtime")
                } footer: {
                    Text("Live microphone audio is sent to Alibaba Cloud for transcription.")
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

                    if viewModel.settingsStore.selectedProvider == .custom {
                        TextField(
                            "https://api.example.com/v1",
                            text: $viewModel.settingsStore.customBaseURL
                        )
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)

                        if !viewModel.settingsStore.discoveredCustomModels.isEmpty {
                            Picker("Model", selection: $viewModel.settingsStore.customModelID) {
                                ForEach(viewModel.settingsStore.discoveredCustomModels, id: \.self) { modelID in
                                    Text(modelID).tag(modelID)
                                }
                                if !viewModel.settingsStore.discoveredCustomModels.contains(
                                    viewModel.settingsStore.customModelID),
                                    !viewModel.settingsStore.customModelID.isEmpty
                                {
                                    Text(viewModel.settingsStore.customModelID).tag(
                                        viewModel.settingsStore.customModelID)
                                }
                            }
                        }

                        TextField("Model ID", text: $viewModel.settingsStore.customModelID)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } else {
                        Picker("Model", selection: $viewModel.settingsStore.selectedModel) {
                            ForEach(RewriteModel.availableModels(for: viewModel.settingsStore.selectedProvider)) {
                                model in
                                Text(model.displayName).tag(model)
                            }
                        }
                    }
                }

                Section("API Key") {
                    SecureField(
                        viewModel.settingsStore.selectedProvider.apiKeyPlaceholder,
                        text: $viewModel.apiKeyInput
                    )
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
        }
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
