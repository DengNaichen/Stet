#if os(macOS)
    import SwiftUI
    import StetCore

    struct MacTranscriptionSettingsView: View {
        @StateObject private var viewModel = MacAudioSettingsViewModel()

        var body: some View {
            Form {
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
                                "Parakeet model isn't downloaded yet. Stet will fall back to Fun-ASR Nano until you download it below."
                            )
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                        }

                        if viewModel.localTranscriptionEngine == .funASRNano,
                            !viewModel.isFunASRNanoDownloaded
                        {
                            Text(
                                "Fun-ASR Nano isn't downloaded yet. Download it below before dictating."
                            )
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                        }

                        if viewModel.localTranscriptionEngine == .appleSpeech,
                            !viewModel.appleSpeechAssetState.isInstalled
                        {
                            Text(viewModel.appleSpeechAssetState.statusText)
                                .font(.system(size: 11))
                                .foregroundStyle(.orange)
                        }

                        Divider().padding(.vertical, 4)

                        VStack(spacing: 12) {
                            TranscriptionModelRow(
                                name: "Fun-ASR Nano (Chinese / English / Japanese)",
                                isDownloaded: viewModel.isFunASRNanoDownloaded,
                                isDownloading: viewModel.isFunASRNanoDownloading,
                                errorMessage: viewModel.funASRNanoErrorMessage,
                                onDownload: { viewModel.downloadFunASRNanoModel() },
                                onReveal: { viewModel.openFunASRNanoFolder() }
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

                            AppleSpeechModelRow(
                                state: viewModel.appleSpeechAssetState,
                                onDownload: { viewModel.downloadAppleSpeechModel() }
                            )
                        }
                    }
                } header: {
                    Text("Local Transcription")
                }
            }
            .macSettingsFormStyle()
            .padding(.bottom, MacUI.SettingsViewMetrics.formBottomPadding)
            .task {
                viewModel.onAppear()
            }
            .onDisappear {
                viewModel.onDisappear()
            }
        }

        private struct AppleSpeechModelRow: View {
            let state: AppleSpeechAssetState
            let onDownload: () -> Void

            var body: some View {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Apple Speech (Experimental)")
                                .font(.system(size: 12, weight: .medium))
                            Text("On-device SpeechAnalyzer / SpeechTranscriber")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Text(state.statusText)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if state.isDownloading {
                            ProgressView()
                                .controlSize(.small)
                        }

                        Button(state.isInstalled ? "Installed" : state.errorMessage == nil ? "Download" : "Retry") {
                            onDownload()
                        }
                        .disabled(!state.canDownload)
                    }

                    if let message = state.errorMessage {
                        Text(message)
                            .font(.system(size: 10))
                            .foregroundStyle(.red)
                    }
                }
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
