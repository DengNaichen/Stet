#if os(macOS)
    import SwiftUI

    struct MacDictationSettingsView: View {
        @StateObject private var viewModel = MacDictationSettingsViewModel()
        @State private var message: LocalizedStringKey?

        var body: some View {
            LinearPageContainer(title: "Shortcut") {
                LinearSectionGroup("Shortcut") {
                    MacHotKeySettingsSectionView(hotkey: .dictation, compactRow: true) { shortcut in
                        message = shortcut.map { "Shortcut updated to \($0)." } ?? "Shortcut cleared."
                    }
                }

                LinearSectionGroup(
                    "Feedback",
                    footer: "Stet can play a sound and show a notification after your words are inserted."
                ) {
                    LinearSettingRow("Interaction sounds") {
                        Toggle("", isOn: $viewModel.interactionSoundsEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .tint(MacUI.LinearBrand.accent)
                    }

                    LinearSettingRow("Notify when dictation completes") {
                        Toggle("", isOn: $viewModel.dictationCompletionNotificationsEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .tint(MacUI.LinearBrand.accent)
                    }

                    LinearSettingRow("Mute background audio") {
                        Toggle("", isOn: $viewModel.pauseMediaDuringDictation)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .tint(MacUI.LinearBrand.accent)
                    }
                }

                if let message {
                    LinearInlineBanner(
                        systemImage: "checkmark.circle.fill",
                        tint: MacUI.Foreground.secondaryColor,
                        message: message
                    )
                }
            }
            .task {
                viewModel.load()
            }
        }
    }
#endif
