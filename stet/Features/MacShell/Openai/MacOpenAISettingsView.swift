#if os(macOS)
    import SwiftUI

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
                                        HStack {
                                            Text(provider.displayName)
                                            if provider.isDisabled {
                                                Text(NSLocalizedString("(Unavailable)", comment: ""))
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
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
