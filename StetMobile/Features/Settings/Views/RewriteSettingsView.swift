import StetAI
import StetCore
import SwiftUI

struct RewriteSettingsView: View {
    @ObservedObject var viewModel: RewriteSettingsViewModel

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Rewrite Toggle
                Section {
                    Toggle("Transcript Improvement", isOn: $viewModel.settingsStore.isRewriteEnabled)
                } footer: {
                    Text("When enabled, transcripts are cleaned up by AI before display.")
                }

                // MARK: - Provider Selection
                Section("AI Provider") {
                    Picker("Provider", selection: $viewModel.settingsStore.selectedProvider) {
                        ForEach(viewModel.availableProviders) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                    .onChange(of: viewModel.settingsStore.selectedProvider) {
                        viewModel.onProviderChanged()
                    }
                }

                // MARK: - API Key
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

                // MARK: - Model Selection
                Section("Model") {
                    TextField("Model name", text: $viewModel.settingsStore.selectedModel)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle("AI Settings")
        }
    }
}
