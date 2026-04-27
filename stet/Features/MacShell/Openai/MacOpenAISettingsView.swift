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
                        Toggle("Transcript improvement", isOn: $viewModel.isRewriteEnabled)

                        Text("Stet can refine and improve the precision of your transcriptions using AI.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)

                        if viewModel.isRewriteEnabled {
                            Divider().padding(.vertical, 4)

                            MacSettingsValueRow(title: "Refine Model") {
                                Picker("", selection: $viewModel.unifiedProvider) {
                                    ForEach(MacOpenAISettingsViewModel.UnifiedAIProvider.allCases) { provider in
                                        Text(provider.displayName).tag(provider)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .frame(width: controlWidth, alignment: .trailing)
                            }
                        }
                    }
                } header: {
                    Text("Refine")
                }

                if viewModel.unifiedProvider == .appleIntelligence {
                    Section {
                        Text(
                            "Uses the on-device Apple Intelligence model to refine transcripts locally. Availability depends on Apple Intelligence being enabled and ready on this Mac."
                        )
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    } header: {
                        Text("Apple Intelligence")
                    }
                }

                ForEach(viewModel.visibleCredentialProviders) { provider in
                    Section {
                        VStack(alignment: .leading, spacing: MacUI.SettingsViewMetrics.cardContentSpacing) {
                            Text("Provide your API key to use \(provider.displayName) directly.")
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
                                Button("Save Key") {
                                    viewModel.saveCredential(for: provider)
                                }

                                Button("Remove Key", role: .destructive) {
                                    viewModel.clearCredential(for: provider)
                                }
                                .foregroundStyle(.red)
                            }
                        }
                    } header: {
                        Text("\(provider.displayName) Settings")
                    }
                }
            }
            .onAppear {
                viewModel.load()
            }
        }
    }
#endif
