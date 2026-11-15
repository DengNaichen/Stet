#if os(macOS)
    import SwiftUI

    struct MacGeneralSettingsView: View {
        @EnvironmentObject private var settingsShellViewModel: MacSettingsShellViewModel
        @Environment(MacAppUpdateViewModel.self) private var appUpdateViewModel
        @Environment(MacCompatibilityViewModel.self) private var compatibilityViewModel

        @StateObject private var viewModel = MacGeneralSettingsViewModel()

        var body: some View {
            LinearPageContainer(title: "General") {
                appBehaviorSection
                updatesSection
                compatibilitySection
                #if DEBUG
                    debugSection
                #endif
                if let feedback = viewModel.feedback {
                    LinearInlineBanner(
                        systemImage: feedback.isError ? "exclamationmark.triangle.fill" : "info.circle.fill",
                        tint: feedback.isError ? MacUI.Foreground.error : MacUI.Foreground.secondaryColor,
                        text: feedback.message
                    )
                }
            }
            .task {
                viewModel.configure(appModel: settingsShellViewModel, appUpdateManager: appUpdateViewModel)
                viewModel.load()
            }
        }

        private var appBehaviorSection: some View {
            LinearSectionGroup(
                "Application",
                footer: "Stet stays in the menu bar for quick access even when the dock icon is hidden."
            ) {
                LinearSettingRow("Launch at Login") {
                    Toggle("", isOn: $viewModel.managedSettings.launchAtLogin)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .tint(MacUI.LinearBrand.accent)
                }

                LinearSettingRow("Show in Dock") {
                    Toggle("", isOn: $viewModel.managedSettings.showInDock)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .tint(MacUI.LinearBrand.accent)
                }
            }
        }

        private var updatesSection: some View {
            LinearSectionGroup("Updates") {
                LinearSettingRow("Check for updates automatically") {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { viewModel.updateSettings.automaticallyChecksForUpdates },
                            set: { viewModel.setAutomaticallyChecksForUpdates($0) }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(MacUI.LinearBrand.accent)
                    .disabled(!viewModel.updateSettings.isConfigured)
                }

                LinearSettingRow("Check for Updates") {
                    HStack(spacing: 8) {
                        if viewModel.updateSettings.isCheckingForUpdates {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Button("Check for Updates") {
                            viewModel.checkForUpdates()
                        }
                        .buttonStyle(.bordered)
                        .disabled(
                            viewModel.updateSettings.isCheckingForUpdates
                                || !viewModel.updateSettings.canCheckForUpdates
                        )
                    }
                }
            }
        }

        private var compatibilitySection: some View {
            LinearSectionGroup(
                "App Compatibility",
                footer: "Update compatibility fixes for pasting into other apps."
            ) {
                MacCompatibilityUpdateControls(state: compatibilityViewModel.refreshState) {
                    Task { await compatibilityViewModel.refresh() }
                }
            }
        }

        #if DEBUG
            private var debugSection: some View {
                LinearSectionGroup(
                    "Debug",
                    footer: "You can also launch with `--force-onboarding` or `STET_FORCE_ONBOARDING=1`."
                ) {
                    LinearSettingRow("Always show onboarding while debugging") {
                        Toggle("", isOn: $viewModel.debugForceOnboarding)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .tint(MacUI.LinearBrand.accent)
                    }

                    LinearSettingRow("Restart Onboarding Now") {
                        Button("Restart Onboarding Now") {
                            viewModel.restartOnboarding()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        #endif
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
