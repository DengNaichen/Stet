#if os(macOS)
    import SwiftUI

    struct MacDictationSettingsView: View {
        @StateObject private var viewModel = MacDictationSettingsViewModel()
        @State private var message: String?

        var body: some View {
            Form {
                Section {
                    MacHotKeySettingsSectionView(hotkey: .dictation) { shortcut in
                        message = shortcut.map { "Shortcut updated to \($0)." } ?? "Shortcut cleared."
                    }
                } header: {
                    Text("Shortcut")
                }

                Section {
                    Toggle("Interaction sounds", isOn: $viewModel.interactionSoundsEnabled)
                    Toggle(
                        "Notify when dictation completes",
                        isOn: $viewModel.dictationCompletionNotificationsEnabled
                    )
                    Toggle("Mute background audio", isOn: $viewModel.pauseMediaDuringDictation)
                } header: {
                    Text("Feedback")
                } footer: {
                    Text(
                        "Stet can play a sound and show a notification after your words are inserted."
                    )
                }

                if let message {
                    Section {
                        Text(message)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .padding(.bottom, MacUI.SettingsViewMetrics.formBottomPadding)
            .task {
                viewModel.load()
            }
        }
    }
#endif
