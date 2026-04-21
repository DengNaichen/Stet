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

                Section {
                    VStack(alignment: .leading, spacing: MacUI.SettingsViewMetrics.cardContentSpacing) {
                        if viewModel.localWhisperCustomPath.isEmpty {
                            Text(viewModel.localWhisperStatusMessage)
                                .font(.system(size: 12))
                                .foregroundStyle(viewModel.localWhisperNeedsAttention ? .orange : .secondary)
                        } else {
                            Text(URL(fileURLWithPath: viewModel.localWhisperCustomPath).lastPathComponent)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .help(viewModel.localWhisperCustomPath)
                        }

                        HStack(spacing: 12) {
                            Button("Choose model…") {
                                viewModel.selectLocalWhisperModel()
                            }

                            if !viewModel.localWhisperCustomPath.isEmpty {
                                Button("Clear", role: .destructive) {
                                    viewModel.clearLocalWhisperModel()
                                }
                            }
                        }
                    }
                } header: {
                    Text("Local Whisper")
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
