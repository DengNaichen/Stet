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
                        MacSettingsValueRow(title: "How to use AI") {
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
                } header: {
                    Text("Refine")
                }

                if viewModel.executionMode == .managed {
                    Section {
                        Text("Stet account provides high-quality AI features without needing your own API keys.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        
                        Button("Manage Account") {
                            onManageAccount?()
                        }
                    } header: {
                        Text("Stet Account")
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

                Section {
                    VStack(alignment: .leading, spacing: MacUI.SettingsViewMetrics.cardContentSpacing) {
                        Text("Use a local Whisper model for offline transcription.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            
                        HStack(spacing: 12) {
                            Button("Reveal in Finder") {
                                viewModel.openLocalWhisperFolder()
                            }
                        }
                    }
                } header: {
                    Text("Local Whisper")
                }
            }
        }
    }
#endif
