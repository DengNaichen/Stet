#if os(macOS)
    import SwiftUI

    struct MacGeneralSettingsView: View {
        @EnvironmentObject private var settingsShellViewModel: MacSettingsShellViewModel
        @Environment(MacAppUpdateViewModel.self) private var appUpdateViewModel

        var scrollTarget: MacSettingsTargetSection? = nil
        var scrollTrigger: Int = 0

        @StateObject private var viewModel = MacGeneralSettingsViewModel()

        var body: some View {
            LinearPageContainer(
                title: "General",
                scrollTarget: scrollTarget,
                scrollTrigger: scrollTrigger
            ) {
                appBehaviorSection
                    .id(MacSettingsTargetSection.application)
                updatesSection
                    .id(MacSettingsTargetSection.updates)
                #if DEBUG
                    debugSection
                #endif
                if let feedback = viewModel.feedback {
                    if feedback.isError {
                        LinearInlineBanner(
                            systemImage: "exclamationmark.triangle.fill",
                            tint: MacUI.Foreground.error,
                            text: feedback.message
                        )
                    } else {
                        LinearInlineBanner(
                            systemImage: "info.circle.fill",
                            tint: MacUI.Foreground.secondaryColor,
                            message: LocalizedStringKey(feedback.message)
                        )
                    }
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
#endif
