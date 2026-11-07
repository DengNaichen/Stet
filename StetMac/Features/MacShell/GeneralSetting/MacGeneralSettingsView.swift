#if os(macOS)
    import SwiftUI

    struct MacGeneralSettingsView: View {
        @EnvironmentObject private var settingsShellViewModel: MacSettingsShellViewModel
        @EnvironmentObject private var appUpdateViewModel: MacAppUpdateViewModel
        @EnvironmentObject private var compatibilityViewModel: MacCompatibilityViewModel

        @StateObject private var viewModel = MacGeneralSettingsViewModel()

        var body: some View {
            Form {
                appBehaviorSection
                updatesSection
                compatibilitySection
                #if DEBUG
                    debugSection
                #endif
                feedbackSection
            }
            .macSettingsFormStyle()
            .padding(.bottom, MacUI.SettingsViewMetrics.formBottomPadding)
            .task {
                viewModel.configure(appModel: settingsShellViewModel, appUpdateManager: appUpdateViewModel)
                viewModel.load()
            }
        }

        private var appBehaviorSection: some View {
            Section {
                Toggle("Launch at Login", isOn: $viewModel.managedSettings.launchAtLogin)
                Toggle("Show in Dock", isOn: $viewModel.managedSettings.showInDock)
            } header: {
                Text("Application")
            } footer: {
                Text("Stet stays in the menu bar for quick access even when the dock icon is hidden.")
            }
        }

        private var updatesSection: some View {
            Section {
                Toggle(
                    "Check for updates automatically",
                    isOn: Binding(
                        get: { viewModel.updateSettings.automaticallyChecksForUpdates },
                        set: { viewModel.setAutomaticallyChecksForUpdates($0) }
                    )
                )
                .disabled(!viewModel.updateSettings.isConfigured)

                Button("Check for Updates") {
                    viewModel.checkForUpdates()
                }
                .disabled(
                    viewModel.updateSettings.isCheckingForUpdates || !viewModel.updateSettings.canCheckForUpdates)
            } header: {
                Text("Updates")
            }
        }

        private var compatibilitySection: some View {
            Section {
                MacCompatibilityUpdateControls(state: compatibilityViewModel.refreshState) {
                    Task { await compatibilityViewModel.refresh() }
                }
            } header: {
                Text("App Compatibility")
            } footer: {
                Text("Update compatibility fixes for pasting into other apps.")
            }
        }

        #if DEBUG
            private var debugSection: some View {
                Section {
                    Toggle("Always show onboarding while debugging", isOn: $viewModel.debugForceOnboarding)

                    Button("Restart Onboarding Now") {
                        viewModel.restartOnboarding()
                    }
                } header: {
                    Text("Debug")
                } footer: {
                    Text("You can also launch with `--force-onboarding` or `STET_FORCE_ONBOARDING=1`.")
                }
            }
        #endif

        @ViewBuilder
        private var feedbackSection: some View {
            if let feedback = viewModel.feedback {
                Section {
                    Text(feedback.message)
                        .foregroundStyle(feedback.isError ? MacUI.Foreground.error : MacUI.Foreground.secondaryColor)
                }
            }
        }
    }
    private struct MacCompatibilityUpdateControls: View {
        let state: AppCompatibilityStore.RefreshState
        let check: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: MacUI.SettingsViewMetrics.controlSpacing) {
                Button("Check for Compatibility List Updates", action: check)
                    .disabled(state == .checking)
                HStack(spacing: MacUI.SettingsViewMetrics.labelSpacing) {
                    Image(systemName: statusIcon).frame(width: MacUI.SettingsViewMetrics.statusIconWidth)
                    Text(statusText)
                }
                .font(MacUI.Typography.status)
                .foregroundStyle(statusColor)
                .lineLimit(1)
                .frame(height: MacUI.SettingsViewMetrics.statusRowHeight, alignment: .leading)
                .opacity(state == .idle ? 0 : 1)
                .accessibilityHidden(state == .idle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
