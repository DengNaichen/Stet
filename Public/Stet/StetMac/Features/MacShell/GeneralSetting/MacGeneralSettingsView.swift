#if os(macOS)
    import SwiftUI

    struct MacGeneralSettingsView: View {
        @EnvironmentObject private var settingsShellViewModel: MacSettingsShellViewModel
        @EnvironmentObject private var appUpdateManager: AppUpdateManager

        @StateObject private var viewModel = MacGeneralSettingsViewModel()

        var body: some View {
            Form {
                appBehaviorSection
                dictationSection
                updatesSection
                #if DEBUG
                    debugSection
                #endif
                feedbackSection
            }
            .formStyle(.grouped)
            .padding(.leading, MacUI.SettingsViewMetrics.formHorizontalPadding)
            .padding(.bottom, MacUI.SettingsViewMetrics.formBottomPadding)
            .task {
                viewModel.configure(appModel: settingsShellViewModel, appUpdateManager: appUpdateManager)
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

        private var dictationSection: some View {
            Section {
                Toggle("Interaction sounds", isOn: $viewModel.interactionSoundsEnabled)
                Toggle("Mute background audio", isOn: $viewModel.pauseMediaDuringDictation)
            } header: {
                Text("Dictation")
            } footer: {
                Text("Stet can provide feedback and limit distractions while you are speaking.")
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
                        .foregroundStyle(feedback.isError ? .red : .secondary)
                }
            }
        }
    }
#endif
