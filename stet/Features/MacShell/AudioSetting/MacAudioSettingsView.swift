#if os(macOS)
    import SwiftUI
    import StetCore

    struct MacAudioSettingsView: View {
        @StateObject private var viewModel = MacAudioSettingsViewModel()

        var body: some View {
            Form {
                AudioInputDeviceSettingsSection(
                    deviceManager: viewModel.deviceManager,
                    microphoneTestViewModel: viewModel.microphoneTestViewModel
                )
                Section {
                    VStack(alignment: .leading, spacing: MacUI.SettingsViewMetrics.cardContentSpacing) {
                        Text("Choose which on-device model handles transcription.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)

                        MacSettingsValueRow(title: "Engine") {
                            Picker("", selection: $viewModel.localTranscriptionEngine) {
                                ForEach(viewModel.localTranscriptionEngineOptions, id: \.self) { engine in
                                    Text(engine.displayName).tag(engine)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(width: 240, alignment: .trailing)
                        }

                        if viewModel.localTranscriptionEngine == .fluidAudio, !viewModel.isParakeetDownloaded {
                            Text(
                                "Parakeet model isn't downloaded yet. Stet will fall back to Whisper until you download it below."
                            )
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                        }

                        Divider().padding(.vertical, 4)

                        // Models Management
                        VStack(spacing: 12) {
                            TranscriptionModelRow(
                                name: "Whisper",
                                isDownloaded: viewModel.isWhisperDownloaded,
                                isDownloading: viewModel.isWhisperDownloading,
                                errorMessage: viewModel.whisperErrorMessage,
                                onDownload: { viewModel.downloadWhisperModel() },
                                onReveal: { viewModel.openWhisperFolder() }
                            )

                            Divider()

                            TranscriptionModelRow(
                                name: "Parakeet V3",
                                isDownloaded: viewModel.isParakeetDownloaded,
                                isDownloading: viewModel.isParakeetDownloading,
                                errorMessage: viewModel.parakeetErrorMessage,
                                onDownload: { viewModel.downloadParakeetModel() },
                                onReveal: { viewModel.openParakeetFolder() }
                            )

                            Divider()

                            TranscriptionModelRow(
                                name: "SenseVoice",
                                isDownloaded: viewModel.isSenseVoiceDownloaded,
                                isDownloading: viewModel.isSenseVoiceDownloading,
                                errorMessage: viewModel.senseVoiceErrorMessage,
                                onDownload: { viewModel.downloadSenseVoiceModel() },
                                onReveal: { viewModel.openSenseVoiceFolder() }
                            )
                        }
                    }
                } header: {
                    Text("Local Transcription")
                }
            }
            .formStyle(.grouped)
            .padding(.leading, MacUI.SettingsViewMetrics.formHorizontalPadding)
            .padding(.bottom, MacUI.SettingsViewMetrics.formBottomPadding)
            .task {
                viewModel.onAppear()
            }
            .onDisappear {
                viewModel.onDisappear()
            }
        }

        private struct TranscriptionModelRow: View {
            let name: String
            let isDownloaded: Bool
            let isDownloading: Bool
            let errorMessage: String?
            let onDownload: () -> Void
            let onReveal: () -> Void

            var body: some View {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(name)
                                .font(.system(size: 12, weight: .medium))
                            Text(isDownloaded ? "Downloaded" : "Available")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if isDownloading {
                            ProgressView()
                                .controlSize(.small)
                        }

                        HStack(spacing: 8) {
                            Button(action: onReveal) {
                                Image(systemName: "folder")
                                    .font(.system(size: 12))
                            }
                            .buttonStyle(.bordered)
                            .help("Reveal in Finder")

                            Button(isDownloaded ? "Downloaded" : "Download") {
                                onDownload()
                            }
                            .disabled(isDownloaded || isDownloading)
                        }
                    }

                    if let message = errorMessage {
                        Text(message)
                            .font(.system(size: 10))
                            .foregroundStyle(.red)
                    }
                }
            }
        }
    }
#endif
