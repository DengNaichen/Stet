#if os(macOS)
    import SwiftUI

    struct MacOpenAISettingsView: View {
        @ObservedObject var viewModel: MacOpenAISettingsViewModel
        private let controlWidth: CGFloat = 240

        var body: some View {
            AppForm {
                Section {
                    VStack(alignment: .leading, spacing: MacUI.SettingsViewMetrics.cardContentSpacing) {
                        MacSettingsValueRow(title: "How to use AI") {
                            Picker("", selection: $viewModel.executionMode) {
                                ForEach(AIExecutionMode.allCases) { mode in
                                    Text(mode.title).tag(mode)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(width: controlWidth, alignment: .trailing)
                        }

                        if viewModel.showsProviderConfiguration {
                            MacSettingsValueRow(title: "Transcription provider") {
                                Picker("", selection: $viewModel.transcriptionProvider) {
                                    ForEach(DictationProvider.allCases) { provider in
                                        Text(provider.displayName).tag(provider)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .frame(width: controlWidth, alignment: .trailing)
                            }

                            MacSettingsValueRow(title: "Rewrite provider") {
                                Picker("", selection: $viewModel.rewriteProvider) {
                                    ForEach(DictationProvider.allCases) { provider in
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
                    Text("AI setup")
                }

                if let message = viewModel.missingCredentialMessage {
                    Section {
                        Text(message)
                            .font(.system(size: 12))
                            .foregroundStyle(viewModel.connectionNeedsAttention ? .orange : .secondary)
                    } header: {
                        Text("Requirements")
                    }
                }

                ForEach(viewModel.visibleCredentialProviders) { provider in
                    Section {
                        VStack(alignment: .leading, spacing: MacUI.SettingsViewMetrics.cardContentSpacing) {
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
                                Button("Save key") {
                                    viewModel.saveCredential(for: provider)
                                }

                                Button("Remove key", role: .destructive) {
                                    viewModel.clearCredential(for: provider)
                                }
                            }
                        }
                        .disabled(viewModel.isCredentialEditingDisabled)
                    } header: {
                        Text(viewModel.credentialFieldTitle(for: provider))
                    }
                }
            }
        }
    }
#endif
