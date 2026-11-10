#if os(macOS)
    import SwiftUI
    import StetCore

    struct MacTranscriptionSettingsView: View {
        @StateObject private var viewModel = MacAudioSettingsViewModel()
        @EnvironmentObject private var aneModelSettings: ANEModelSettingsViewModel

        var body: some View {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: MacUI.SettingsViewMetrics.cardContentSpacing) {
                        Text("Choose which on-device model handles transcription.")
                            .font(MacUI.Typography.detail)
                            .foregroundStyle(MacUI.Foreground.secondary)

                        MacSettingsValueRow(title: "Engine") {
                            Picker("", selection: $viewModel.localTranscriptionEngine) {
                                ForEach(viewModel.localTranscriptionEngineOptions, id: \.self) { engine in
                                    Text(engine.displayName).tag(engine)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(width: MacUI.SettingsViewMetrics.controlWidth, alignment: .trailing)
                        }

                        if viewModel.localTranscriptionEngine == .fluidAudio, !viewModel.isParakeetDownloaded {
                            Text(
                                "Parakeet model isn't downloaded yet. Stet will fall back to Fun-ASR Nano until you download it below."
                            )
                            .font(MacUI.Typography.detail)
                            .foregroundStyle(MacUI.Foreground.warning)
                        }

                        if viewModel.localTranscriptionEngine == .funASRNano,
                            !viewModel.isFunASRNanoDownloaded
                        {
                            Text(
                                "Fun-ASR Nano isn't downloaded yet. Download it below before dictating."
                            )
                            .font(MacUI.Typography.detail)
                            .foregroundStyle(MacUI.Foreground.warning)
                        }

                        if viewModel.localTranscriptionEngine == .appleSpeech,
                            !viewModel.appleSpeechAssetState.isInstalled
                        {
                            Text(viewModel.appleSpeechAssetState.statusText)
                                .font(MacUI.Typography.detail)
                                .foregroundStyle(MacUI.Foreground.warning)
                        }

                        Divider().padding(.vertical, MacUI.SettingsViewMetrics.dividerVerticalPadding)

                        VStack(spacing: MacUI.SettingsViewMetrics.rowContentSpacing) {
                            TranscriptionModelRow(
                                name: "Fun-ASR Nano (Chinese / English / Japanese)",
                                isDownloaded: viewModel.isFunASRNanoDownloaded,
                                isDownloading: viewModel.isFunASRNanoDownloading,
                                errorMessage: viewModel.funASRNanoErrorMessage,
                                onDownload: { viewModel.downloadFunASRNanoModel() },
                                onReveal: { viewModel.openFunASRNanoFolder() }
                            )

                            ANEModelSettingsRow(viewModel: aneModelSettings)

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
                VStack(alignment: .leading, spacing: MacUI.SettingsViewMetrics.detailSpacing) {
                    HStack(spacing: MacUI.SettingsViewMetrics.rowContentSpacing) {
                        VStack(alignment: .leading, spacing: MacUI.SettingsViewMetrics.compactDetailSpacing) {
                            Text("Apple Speech (Experimental)")
                                .font(MacUI.Typography.itemTitle)
                            Text("On-device SpeechAnalyzer / SpeechTranscriber")
                                .font(MacUI.Typography.detail)
                                .foregroundStyle(MacUI.Foreground.secondary)
                            Text(state.statusText)
                                .font(MacUI.Typography.detail)
                                .foregroundStyle(MacUI.Foreground.secondary)
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
                            .font(MacUI.Typography.footnote)
                            .foregroundStyle(MacUI.Foreground.error)
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
                VStack(alignment: .leading, spacing: MacUI.SettingsViewMetrics.detailSpacing) {
                    HStack(spacing: MacUI.SettingsViewMetrics.rowContentSpacing) {
                        VStack(alignment: .leading, spacing: MacUI.SettingsViewMetrics.compactDetailSpacing) {
                            Text(name)
                                .font(MacUI.Typography.itemTitle)
                            Text(isDownloaded ? "Downloaded" : "Available")
                                .font(MacUI.Typography.detail)
                                .foregroundStyle(MacUI.Foreground.secondary)
                        }

                        Spacer()

                        if isDownloading {
                            ProgressView()
                                .controlSize(.small)
                        }

                        HStack(spacing: MacUI.SettingsViewMetrics.controlSpacing) {
                            Button(action: onReveal) {
                                Image(systemName: "folder")
                                    .font(MacUI.Typography.actionIcon)
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
                            .font(MacUI.Typography.footnote)
                            .foregroundStyle(MacUI.Foreground.error)
                    }
                }
            }
        }
    }
#endif
