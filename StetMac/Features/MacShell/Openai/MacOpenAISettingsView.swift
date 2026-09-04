#if os(macOS)
    import SwiftUI
    import StetCore

    struct MacOpenAISettingsView: View {
        @ObservedObject var viewModel: MacOpenAISettingsViewModel
        var onManageAccount: (() -> Void)? = nil
        private let controlWidth: CGFloat = 240

        var body: some View {
            AppForm {
                Section {
                    VStack(alignment: .leading, spacing: MacUI.SettingsViewMetrics.cardContentSpacing) {
                        Toggle(
                            NSLocalizedString("Transcript improvement", comment: ""), isOn: $viewModel.isRewriteEnabled)

                        Text(
                            NSLocalizedString(
                                "Stet can refine and improve the precision of your transcriptions using AI.",
                                comment: "")
                        )
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                        if viewModel.isRewriteEnabled {
                            Divider().padding(.vertical, 4)

                            MacSettingsValueRow(title: NSLocalizedString("Refine Model", comment: "")) {
                                Picker("", selection: $viewModel.unifiedProvider) {
                                    ForEach(MacOpenAISettingsViewModel.UnifiedAIProvider.allCases) { provider in
                                        Text(
                                            provider.isDisabled
                                                ? "\(provider.displayName) (Unavailable)" : provider.displayName
                                        )
                                        .tag(provider)
                                        .disabled(provider.isDisabled)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .frame(width: controlWidth, alignment: .trailing)
                            }

                            if !viewModel.availableModels.isEmpty {
                                MacSettingsValueRow(title: NSLocalizedString("Preferred Model", comment: "")) {
                                    Picker("", selection: $viewModel.selectedModel) {
                                        ForEach(viewModel.availableModels) { model in
                                            Text(model.displayName).tag(model)
                                        }
                                    }
                                    .labelsHidden()
                                    .pickerStyle(.menu)
                                    .frame(width: controlWidth, alignment: .trailing)
                                }
                            }
                        }
                    }
                } header: {
                    Text(NSLocalizedString("Refine", comment: ""))
                }

                if viewModel.unifiedProvider == .appleIntelligence {
                    Section {
                        Text(
                            NSLocalizedString(
                                "Uses the on-device Apple Intelligence model to refine transcripts locally. Availability depends on Apple Intelligence being enabled and ready on this Mac.",
                                comment: "")
                        )
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    } header: {
                        Text(NSLocalizedString("Apple Intelligence", comment: ""))
                    }
                }

                if viewModel.isRewriteEnabled, viewModel.unifiedProvider == .custom {
                    Section {
                        VStack(alignment: .leading, spacing: MacUI.SettingsViewMetrics.cardContentSpacing) {
                            Text(
                                NSLocalizedString(
                                    "Use any OpenAI-compatible API. Stet lists models from GET /models, or you can type a model ID.",
                                    comment: "")
                            )
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)

                            MacSettingsValueRow(title: NSLocalizedString("Base URL", comment: "")) {
                                TextField(
                                    "https://api.example.com/v1",
                                    text: $viewModel.customBaseURL
                                )
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                                .frame(width: controlWidth, alignment: .trailing)
                            }

                            SecureField(
                                viewModel.credentialPlaceholder(for: .custom),
                                text: $viewModel.customAPIKey
                            )
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))

                            if !viewModel.discoveredCustomModels.isEmpty {
                                MacSettingsValueRow(title: NSLocalizedString("Preferred Model", comment: "")) {
                                    Picker("", selection: $viewModel.customModelID) {
                                        ForEach(viewModel.discoveredCustomModels, id: \.self) { modelID in
                                            Text(modelID).tag(modelID)
                                        }
                                        if !viewModel.discoveredCustomModels.contains(viewModel.customModelID),
                                            !viewModel.customModelID.isEmpty
                                        {
                                            Text(viewModel.customModelID).tag(viewModel.customModelID)
                                        }
                                    }
                                    .labelsHidden()
                                    .pickerStyle(.menu)
                                    .frame(width: controlWidth, alignment: .trailing)
                                }
                            }

                            MacSettingsValueRow(title: NSLocalizedString("Model ID", comment: "")) {
                                TextField("llama3.1", text: $viewModel.customModelID)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(.body, design: .monospaced))
                                    .frame(width: controlWidth, alignment: .trailing)
                            }

                            HStack(spacing: 12) {
                                Button(NSLocalizedString("Load Models", comment: "")) {
                                    Task { await viewModel.loadCustomModels() }
                                }
                                .disabled(viewModel.customModelProbeState == .loading)

                                Button(NSLocalizedString("Save Key", comment: "")) {
                                    viewModel.saveCustomEndpoint()
                                }

                                Button(NSLocalizedString("Remove Key", comment: ""), role: .destructive) {
                                    viewModel.clearCredential(for: .custom)
                                }
                                .foregroundStyle(.red)
                            }

                            switch viewModel.customModelProbeState {
                            case .idle, .loading:
                                EmptyView()
                            case .loaded(let count):
                                Text(
                                    count == 0
                                        ? NSLocalizedString(
                                            "No models were returned. Enter a model ID below.", comment: "")
                                        : String(
                                            format: NSLocalizedString("%d models found.", comment: ""),
                                            count)
                                )
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            case .failed(let message):
                                Text(message)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.red)
                            }
                        }
                    } header: {
                        Text(NSLocalizedString("Custom Endpoint", comment: ""))
                    }
                }

                ForEach(viewModel.visibleCredentialProviders) { provider in
                    Section {
                        VStack(alignment: .leading, spacing: MacUI.SettingsViewMetrics.cardContentSpacing) {
                            Text(
                                String(
                                    format: NSLocalizedString("Provide your API key to use %@ directly.", comment: ""),
                                    provider.displayName)
                            )
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)

                            SecureField(
                                viewModel.credentialPlaceholder(for: provider),
                                text: Binding(
                                    get: { viewModel.apiKey(for: provider) },
                                    set: { viewModel.setAPIKey($0, for: provider) }
                                )
                            )
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))

                            HStack(spacing: 12) {
                                Button(NSLocalizedString("Save Key", comment: "")) {
                                    viewModel.saveCredential(for: provider)
                                }

                                Button(NSLocalizedString("Remove Key", comment: ""), role: .destructive) {
                                    viewModel.clearCredential(for: provider)
                                }
                                .foregroundStyle(.red)
                            }
                        }
                    } header: {
                        Text(String(format: NSLocalizedString("%@ Settings", comment: ""), provider.displayName))
                    }
                }
            }
            .onAppear {
                viewModel.load()
            }
        }
    }
#endif
