#if os(macOS)
    import SwiftUI

    struct MacGeneralSettingsView: View {
        @EnvironmentObject private var settingsShellViewModel: MacSettingsShellViewModel
        @EnvironmentObject private var appUpdateManager: AppUpdateManager

        @StateObject private var viewModel = MacGeneralSettingsViewModel()

        var body: some View {
            Form {
                captureSection
                interactionSoundsSection
                appBehaviorSection
                #if DEBUG
                    debugSection
                #endif
                updatesSection
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

        private var captureSection: some View {
            Section {
                Toggle(
                    "Mute other audio during dictation and restore afterward",
                    isOn: $viewModel.pauseMediaDuringDictation
                )
            } header: {
                Text("Capture")
            }
        }

        private var interactionSoundsSection: some View {
            Section {
                Toggle("Enable interaction sounds", isOn: $viewModel.interactionSoundsEnabled)

                if viewModel.interactionSoundsEnabled {
                    Button("Preview Sound") {
                        viewModel.previewSound()
                    }
                }
            } header: {
                Text("Interaction Sounds")
            } footer: {
                if viewModel.interactionSoundsEnabled {
                    Text("Stet uses the default sound pair for recording start and finish.")
                }
            }
        }

        private var appBehaviorSection: some View {
            Section {
                Toggle("Launch at Login", isOn: $viewModel.managedSettings.launchAtLogin)
                Toggle("Show in Dock", isOn: $viewModel.managedSettings.showInDock)
            } header: {
                Text("App Behavior")
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
                .disabled(viewModel.updateSettings.isCheckingForUpdates || !viewModel.updateSettings.canCheckForUpdates)
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
