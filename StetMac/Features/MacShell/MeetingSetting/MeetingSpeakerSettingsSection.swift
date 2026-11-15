#if os(macOS)
    import SwiftUI

    struct MeetingSpeakerSettingsSection: View {
        @ObservedObject var settings: MeetingSpeakerSettings
        let isRecording: Bool

        var body: some View {
            LinearSectionGroup("Speaker Separation") {
                LinearSettingRow(
                    "Separate Speakers",
                    subtitle: "Label different speakers in the meeting transcript. Changes apply to the next meeting."
                ) {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { settings.isEnabled },
                            set: { settings.requestEnabled($0) }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(MacUI.LinearBrand.accent)
                    .disabled(settings.isWorking)
                }

                modelStatus
                    .padding(.horizontal, MacUI.LinearMetrics.rowHorizontalPadding)
                    .padding(.top, 2)
                    .padding(.bottom, 10)
            }
            .confirmationDialog(
                "Download Speaker Separation Model?",
                isPresented: $settings.showsDownloadPrompt,
                titleVisibility: .visible
            ) {
                Button("Download and Enable") { settings.downloadAndEnable() }
                Button("Not Now", role: .cancel) {}
            } message: {
                Text(
                    "Download approximately 241 MB once to separate speakers on this Mac. You can record ordinary meetings while it downloads."
                )
            }
            .task { settings.refresh() }
        }

        @ViewBuilder
        private var modelStatus: some View {
            switch settings.state {
            case .missing:
                HStack {
                    Text("Speaker separation model not installed")
                        .font(MacUI.LinearTypography.rowSubtitle)
                        .foregroundStyle(MacUI.Foreground.secondary)
                    Spacer()
                    Button("Download Speaker Separation Model") { settings.showsDownloadPrompt = true }
                        .buttonStyle(.bordered)
                }
            case .checking:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Checking model…")
                        .font(MacUI.LinearTypography.rowSubtitle)
                        .foregroundStyle(MacUI.Foreground.secondary)
                }
            case .downloading(let fraction):
                HStack(spacing: 12) {
                    ProgressView(value: fraction) {
                        Text("Downloading speaker model: \(Int(fraction * 100))%")
                            .font(MacUI.LinearTypography.rowSubtitle)
                    }
                    Spacer()
                    Button("Cancel Download") { settings.cancelDownload() }
                        .buttonStyle(.bordered)
                }
            case .validating:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Verifying model…")
                        .font(MacUI.LinearTypography.rowSubtitle)
                        .foregroundStyle(MacUI.Foreground.secondary)
                    Spacer()
                    Button("Cancel Download") { settings.cancelDownload() }
                        .buttonStyle(.bordered)
                }
            case .ready:
                HStack {
                    if isRecording {
                        Text("Model ready. Changes take effect next meeting.")
                            .font(MacUI.LinearTypography.rowSubtitle)
                            .foregroundStyle(MacUI.Foreground.secondary)
                    } else {
                        Text("Speaker separation model ready")
                            .font(MacUI.LinearTypography.rowSubtitle)
                            .foregroundStyle(MacUI.Foreground.secondary)
                    }
                    Spacer()
                    LinearBadge(text: "Ready", tint: MacUI.Foreground.success, showDot: true)
                }
            case .failed(let message):
                HStack(spacing: 10) {
                    Text(message)
                        .font(MacUI.LinearTypography.rowSubtitle)
                        .foregroundStyle(MacUI.Foreground.error)
                    Spacer()
                    Button("Retry Download and Enable") { settings.downloadAndEnable() }
                        .buttonStyle(.bordered)
                }
            }
        }
    }
#endif
