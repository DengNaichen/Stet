#if os(macOS)
    import SwiftUI

    struct MeetingSpeakerSettingsSection: View {
        @ObservedObject var settings: MeetingSpeakerSettings
        let isRecording: Bool

        var body: some View {
            Section {
                Toggle(
                    "Separate Speakers",
                    isOn: Binding(
                        get: { settings.isEnabled },
                        set: { settings.requestEnabled($0) }
                    )
                )
                .disabled(settings.isWorking)
                Text("Label different speakers in the meeting transcript. Changes apply to the next meeting.")
                    .foregroundStyle(.secondary)
                modelStatus
            } header: {
                Text("Speaker Separation")
            }
            .confirmationDialog(
                "Download Speaker Separation Model?", isPresented: $settings.showsDownloadPrompt,
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

        @ViewBuilder private var modelStatus: some View {
            switch settings.state {
            case .missing:
                Button("Download Speaker Separation Model") { settings.showsDownloadPrompt = true }
            case .checking:
                ProgressView("Checking model…")
            case .downloading(let fraction):
                ProgressView(value: fraction) {
                    Text("Downloading speaker model: \(Int(fraction * 100))%")
                }
                Button("Cancel Download") { settings.cancelDownload() }
            case .validating:
                ProgressView("Verifying model…")
                Button("Cancel Download") { settings.cancelDownload() }
            case .ready:
                Text(
                    LocalizedStringKey(
                        isRecording
                            ? "Model ready. Changes take effect next meeting." : "Speaker separation model ready")
                )
                .foregroundStyle(.secondary)
            case .failed(let message):
                Text(message).foregroundStyle(.secondary)
                Button("Retry Download and Enable") { settings.downloadAndEnable() }
            }
        }
    }
#endif
