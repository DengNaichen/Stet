#if os(macOS)
    import SwiftUI

    struct MacDictationSettingsView: View {
        @Environment(MacCompatibilityViewModel.self) private var compatibilityViewModel

        var scrollTarget: MacSettingsTargetSection? = nil
        var scrollTrigger: Int = 0

        @StateObject private var viewModel = MacDictationSettingsViewModel()
        @State private var message: LocalizedStringKey?

        var body: some View {
            LinearPageContainer(
                title: "Dictation",
                scrollTarget: scrollTarget,
                scrollTrigger: scrollTrigger
            ) {
                LinearSectionGroup("Shortcuts") {
                    MacHotKeySettingsSectionView(hotkey: .dictation, compactRow: true) { shortcut in
                        message =
                            shortcut.map { "Start Dictation shortcut updated to \($0)." }
                            ?? "Start Dictation shortcut cleared."
                    }

                    MacHotKeySettingsSectionView(
                        hotkey: .meeting,
                        compactRow: true,
                        subtitle: "Toggles meeting recording. It is not hold-to-talk."
                    ) { shortcut in
                        message =
                            shortcut.map { "Record Meeting shortcut updated to \($0)." }
                            ?? "Record Meeting shortcut cleared."
                    }
                }
                .id(MacSettingsTargetSection.shortcuts)

                if let message {
                    LinearInlineBanner(
                        systemImage: "checkmark.circle.fill",
                        tint: MacUI.Foreground.secondaryColor,
                        message: message
                    )
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
                .id(MacSettingsTargetSection.feedback)

                LinearSectionGroup(
                    "Pasting & App Compatibility",
                    footer: "Update compatibility fixes for pasting into other apps."
                ) {
                    MacCompatibilityUpdateControls(state: compatibilityViewModel.refreshState) {
                        Task { await compatibilityViewModel.refresh() }
                    }
                }
                .id(MacSettingsTargetSection.pastingCompatibility)
            }
            .task {
                viewModel.load()
            }
        }
    }

    private struct MacCompatibilityUpdateControls: View {
        let state: AppCompatibilityStore.RefreshState
        let check: () -> Void

        var body: some View {
            LinearSettingRow("Compatibility List") {
                HStack(spacing: 10) {
                    if state != .idle {
                        HStack(spacing: 5) {
                            Image(systemName: statusIcon)
                                .font(.system(size: 11))
                            Text(statusText)
                                .font(MacUI.LinearTypography.badge)
                        }
                        .foregroundStyle(statusColor)
                    }

                    Button("Check for Compatibility List Updates", action: check)
                        .buttonStyle(.bordered)
                        .disabled(state == .checking)
                }
            }
        }

        private var statusText: LocalizedStringKey {
            switch state {
            case .idle, .checking: "Checking compatibility list…"
            case .updated, .upToDate: "Updated"
            case .failed: "Check failed. Using current list."
            }
        }

        private var statusIcon: String {
            switch state {
            case .idle, .checking: "arrow.triangle.2.circlepath"
            case .updated, .upToDate: "checkmark.circle.fill"
            case .failed: "exclamationmark.circle.fill"
            }
        }

        private var statusColor: Color {
            switch state {
            case .updated, .upToDate: MacUI.Foreground.success
            case .failed: MacUI.Foreground.error
            case .idle, .checking: MacUI.Foreground.secondaryColor
            }
        }
    }
#endif
