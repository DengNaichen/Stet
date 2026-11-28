#if os(macOS)
    import StetASR
    import StetCore
    import SwiftUI

    struct MacTranscriptionSettingsSections: View {
        @ObservedObject var viewModel: MacAudioSettingsViewModel
        @EnvironmentObject private var aneModelSettings: ANEModelSettingsViewModel

        var body: some View {
            LinearSectionGroup(
                "On-Device Transcription",
                footer: "Audio is transcribed on your Mac. Choose which local engine handles speech-to-text."
            ) {
                LinearSettingRow(
                    "Engine",
                    subtitle: "Choose which on-device model handles transcription."
                ) {
                    Picker("", selection: $viewModel.localTranscriptionEngine) {
                        ForEach(viewModel.localTranscriptionEngineOptions, id: \.self) { engine in
                            Text(LocalizedStringKey(engine.displayName)).tag(engine)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: MacUI.LinearMetrics.pickerWidth, alignment: .trailing)
                }
            }

            if viewModel.localTranscriptionEngine == .fluidAudio, !viewModel.isParakeetDownloaded {
                LinearInlineBanner(
                    systemImage: "exclamationmark.triangle.fill",
                    tint: MacUI.Foreground.warning,
                    message:
                        "Parakeet model isn't downloaded yet. Stet will fall back to Fun-ASR Nano until you download it below."
                )
            }

            if viewModel.localTranscriptionEngine == .funASRNano, !viewModel.isFunASRNanoDownloaded {
                LinearInlineBanner(
                    systemImage: "exclamationmark.triangle.fill",
                    tint: MacUI.Foreground.warning,
                    message: "Fun-ASR Nano isn't downloaded yet. Download it below before dictating."
                )
            }

            if viewModel.localTranscriptionEngine == .appleSpeech, !viewModel.appleSpeechAssetState.isInstalled {
                LinearInlineBanner(
                    systemImage: "exclamationmark.triangle.fill",
                    tint: MacUI.Foreground.warning,
                    text: viewModel.appleSpeechAssetState.statusText
                )
            }

            LinearSectionGroup("Downloaded Models") {
                TranscriptionModelRow(
                    name: "Fun-ASR Nano (Chinese / English / Japanese)",
                    isDownloaded: viewModel.isFunASRNanoDownloaded,
                    isDownloading: viewModel.isFunASRNanoDownloading,
                    errorMessage: viewModel.funASRNanoErrorMessage,
                    onDownload: { viewModel.downloadFunASRNanoModel() },
                    onReveal: { viewModel.openFunASRNanoFolder() }
                )

                ANEModelSettingsRow(viewModel: aneModelSettings)
                    .task(id: viewModel.isFunASRNanoDownloaded) { await aneModelSettings.refresh() }
                    .onChange(of: aneModelSettings.status.ready) { _, _ in viewModel.refreshFunASRNanoStatus() }

                TranscriptionModelRow(
                    name: "Parakeet V3",
                    isDownloaded: viewModel.isParakeetDownloaded,
                    isDownloading: viewModel.isParakeetDownloading,
                    errorMessage: viewModel.parakeetErrorMessage,
                    onDownload: { viewModel.downloadParakeetModel() },
                    onReveal: { viewModel.openParakeetFolder() }
                )

                AppleSpeechModelRow(
                    state: viewModel.appleSpeechAssetState,
                    onDownload: { viewModel.downloadAppleSpeechModel() }
                )
            }
        }

        private struct AppleSpeechModelRow: View {
            let state: AppleSpeechAssetStatus
            let onDownload: () -> Void

            var body: some View {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Apple Speech (Experimental)")
                                .font(MacUI.LinearTypography.rowTitle)
                                .foregroundStyle(MacUI.Foreground.primary)
                            Text("On-device SpeechAnalyzer / SpeechTranscriber · \(state.statusText)")
                                .font(MacUI.LinearTypography.rowSubtitle)
                                .foregroundStyle(MacUI.Foreground.secondary)
                        }

                        Spacer()

                        if state.isDownloading {
                            ProgressView()
                                .controlSize(.small)
                        }

                        let appleSpeechButtonTitle: LocalizedStringKey =
                            state.isInstalled ? "Installed" : state.errorMessage == nil ? "Download" : "Retry"
                        Button(appleSpeechButtonTitle) {
                            onDownload()
                        }
                        .buttonStyle(.bordered)
                        .disabled(!state.canDownload)
                    }

                    if let message = state.errorMessage {
                        Text(message)
                            .font(MacUI.LinearTypography.rowSubtitle)
                            .foregroundStyle(MacUI.Foreground.error)
                    }
                }
                .padding(.horizontal, MacUI.LinearMetrics.rowHorizontalPadding)
                .padding(.vertical, 10)
            }
        }

        private struct TranscriptionModelRow: View {
            let name: LocalizedStringKey
            let isDownloaded: Bool
            let isDownloading: Bool
            let errorMessage: String?
            let onDownload: () -> Void
            let onReveal: () -> Void

            var body: some View {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(name)
                                .font(MacUI.LinearTypography.rowTitle)
                                .foregroundStyle(MacUI.Foreground.primary)
                            Group {
                                if isDownloaded {
                                    Text("Downloaded")
                                } else {
                                    Text("Available")
                                }
                            }
                            .font(MacUI.LinearTypography.rowSubtitle)
                            .foregroundStyle(MacUI.Foreground.secondary)
                        }

                        Spacer()

                        if isDownloading {
                            ProgressView()
                                .controlSize(.small)
                        }

                        HStack(spacing: 8) {
                            Button(action: onReveal) {
                                Image(systemName: "folder")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .buttonStyle(.bordered)
                            .help("Reveal in Finder")
                            .accessibilityLabel("Reveal in Finder")

                            let downloadTitle: LocalizedStringKey = isDownloaded ? "Downloaded" : "Download"
                            Button(downloadTitle) {
                                onDownload()
                            }
                            .buttonStyle(.bordered)
                            .disabled(isDownloaded || isDownloading)
                        }
                    }

                    if let message = errorMessage {
                        Text(message)
                            .font(MacUI.LinearTypography.rowSubtitle)
                            .foregroundStyle(MacUI.Foreground.error)
                    }
                }
                .padding(.horizontal, MacUI.LinearMetrics.rowHorizontalPadding)
                .padding(.vertical, 10)
            }
        }
    }
#endif
