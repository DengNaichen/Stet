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

                Section {
                    VStack(alignment: .leading, spacing: MacUI.SettingsViewMetrics.cardContentSpacing) {
                        Text("Choose which on-device model handles transcription.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)

                        MacSettingsValueRow(title: "Engine") {
                            Picker("", selection: $viewModel.localTranscriptionEngine) {
                                ForEach(viewModel.localTranscriptionEngineOptions, id: \.self) { engine in
                                    Text(engine.displayName)
                                        .tag(engine)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(width: controlWidth, alignment: .trailing)
                        }

                        if viewModel.localTranscriptionEngine == .parakeet, !viewModel.isParakeetDownloaded {
                            Text(
                                "Parakeet model isn't downloaded yet. Stet will fall back to Whisper until you download it below."
                            )
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                        }

                        Divider().padding(.vertical, 4)

                        HStack(spacing: 12) {
                            Button("Reveal Whisper Folder in Finder") {
                                viewModel.openLocalWhisperFolder()
                            }
                        }

                        Divider().padding(.vertical, 4)

                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(viewModel.parakeetDisplayName)
                                    .font(.system(size: 12))
                                Text(viewModel.isParakeetDownloaded ? "Downloaded" : "Not downloaded")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if viewModel.isParakeetDownloading {
                                ProgressView()
                                    .controlSize(.small)
                            }

                            Button(viewModel.isParakeetDownloaded ? "Downloaded" : "Download") {
                                viewModel.downloadParakeetModel()
                            }
                            .disabled(viewModel.isParakeetDownloaded || viewModel.isParakeetDownloading)
                        }

                        if let message = viewModel.parakeetErrorMessage {
                            Text(message)
                                .font(.system(size: 11))
                                .foregroundStyle(.red)
                        }

                    }
                } header: {
                    Text("On-device Transcription")
                }
            }
            .onAppear {
                viewModel.load()
            }
        }
    }
#endif
