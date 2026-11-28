import StetAI
import StetCore
import SwiftUI

struct RewriteSettingsView: View {
    @ObservedObject var viewModel: RewriteSettingsViewModel

    var body: some View {
        NavigationStack {
            Form {
                SpeechRecognitionSection(store: viewModel.speechRecognitionSettingsStore)

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
}

private struct SpeechRecognitionSection: View {
    @ObservedObject var store: SpeechRecognitionSettingsStore

    var body: some View {
        Section("Apple Speech") {
            Picker("Language", selection: $store.selectedLanguage) {
                ForEach(SpeechRecognitionLanguage.allCases) { language in
                    Text(language.displayName).tag(language)
                }
            }

            switch store.assetStatus {
            case .checking:
                ProgressView("Checking language model")
            case .installed:
                Text("Language model installed")
            case .available:
                downloadButton
            case .downloading:
                ProgressView("Downloading language model")
            case .unsupported:
                Text("This language is unavailable on this device.")
            case .failed(let message):
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                downloadButton
            }
        }
        .task(id: store.selectedLanguage) {
            await store.refreshAssetStatus()
        }
    }

    private var downloadButton: some View {
        Button("Download Language Model") {
            Task { try? await store.downloadAssetIfNeeded() }
        }
    }
}
