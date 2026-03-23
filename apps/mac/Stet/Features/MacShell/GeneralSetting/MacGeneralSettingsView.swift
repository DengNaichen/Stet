#if os(macOS)
import SwiftUI

struct MacGeneralSettingsView: View {
    @EnvironmentObject private var settingsShellViewModel: MacSettingsShellViewModel
    @EnvironmentObject private var appUpdateManager: AppUpdateManager

    @StateObject private var viewModel = MacGeneralSettingsViewModel()
    @ObservedObject private var deviceManager = AudioDeviceSelectionManager.shared

    var body: some View {
        Form {
            audioDeviceSection
            captureSection
            interactionSoundsSection
            appearanceSection
            appBehaviorSection
            updatesSection
            feedbackSection
        }
        .formStyle(.grouped)
        .padding(.horizontal, 20)
        .padding(.bottom, 28)
        .task {
            viewModel.configure(appModel: settingsShellViewModel, appUpdateManager: appUpdateManager)
            viewModel.load()
        }
        .onAppear {
            deviceManager.refreshDevices()
        }
    }

    private var audioDeviceSection: some View {
        AudioInputDeviceSettingsSection(deviceManager: deviceManager)
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

    private var appearanceSection: some View {
        Section {
            Picker("Capsule Theme", selection: $viewModel.shaderTheme) {
                ForEach(MacDictationVisualTheme.allCases) { theme in
                    Text(theme.title).tag(theme)
                }
            }
            .pickerStyle(.menu)
        } header: {
            Text("Appearance")
        } footer: {
            Text("Choose the color palette used by the dictation capsule.")
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
