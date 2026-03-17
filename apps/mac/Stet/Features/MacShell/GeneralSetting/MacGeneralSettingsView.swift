#if os(macOS)
import AppKit
import SwiftUI

struct MacGeneralSettingsView: View {
    @EnvironmentObject private var appModel: MacAppModel
    @EnvironmentObject private var appUpdateManager: AppUpdateManager

    @AppStorage(MacPreferences.pauseMediaDuringDictation) private var pauseMediaDuringDictation = false
    @AppStorage(MacPreferences.interactionSoundsEnabled) private var interactionSoundsEnabled = true
    @AppStorage(MacPreferences.hotkeyDebugLoggingEnabled) private var hotkeyDebugLoggingEnabled = false
    @AppStorage(MacPreferences.openAIDebugLoggingEnabled) private var openAIDebugLoggingEnabled = false

    @StateObject private var viewModel = MacGeneralSettingsViewModel()
    @State private var managedSettings = MacGeneralSettingsViewModel.ManagedSettingsState()
    @State private var hasLoadedManagedSettings = false
    @State private var suppressLaunchAtLoginChange = false
    @State private var suppressShowInDockChange = false

    var body: some View {
        Form {
            configurationSection
            captureSection
            interactionSoundsSection
            appBehaviorSection
            updatesSection
            debugLoggingSection
            feedbackSection
        }
        .formStyle(.grouped)
        .padding(.horizontal, 20)
        .padding(.bottom, 28)
        .task {
            managedSettings = viewModel.loadState()
            hasLoadedManagedSettings = true
        }
        .onChange(of: managedSettings.launchAtLogin) { oldValue, newValue in
            handleLaunchAtLoginChange(oldValue: oldValue, newValue: newValue)
        }
        .onChange(of: managedSettings.showInDock) { _, newValue in
            handleShowInDockChange(newValue)
        }
    }

    private var configurationSection: some View {
        Section {
            HStack(spacing: 10) {
                Button("Export Configuration") {
                    viewModel.exportConfiguration()
                }

                Button("Import Configuration") {
                    importConfiguration()
                }
            }
        } header: {
            Text("Configuration")
        } footer: {
            Text("Export or import your current hotkey, dictionary, and behavior settings.")
        }
    }

    private var captureSection: some View {
        Section {
            Toggle("Mute other audio during dictation and restore afterward", isOn: $pauseMediaDuringDictation)
        } header: {
            Text("Capture")
        } footer: {
            Text("Pause media when possible and temporarily silence any remaining system audio while dictation is active.")
        }
    }

    private var interactionSoundsSection: some View {
        Section {
            Toggle("Enable interaction sounds", isOn: $interactionSoundsEnabled)
        } header: {
            Text("Interaction Sounds")
        }
    }

    private var appBehaviorSection: some View {
        Section {
            Toggle("Launch at Login", isOn: $managedSettings.launchAtLogin)
            Toggle("Show in Dock", isOn: $managedSettings.showInDock)
        } header: {
            Text("App Behavior")
        }
    }

    private var updatesSection: some View {
        Section {
            Toggle(
                "Check for updates automatically",
                isOn: Binding(
                    get: { appUpdateManager.automaticallyChecksForUpdates },
                    set: { appUpdateManager.setAutomaticallyChecksForUpdates($0) }
                )
            )
            .disabled(!appUpdateManager.isConfigured)

            Button("Check for Updates") {
                appUpdateManager.checkForUpdates()
            }
            .disabled(appUpdateManager.isChecking || !appUpdateManager.canCheckForUpdates)
        } header: {
            Text("Updates")
        } footer: {
            Text("Automatically check for app updates, or run a manual check at any time.")
        }
    }

    private var debugLoggingSection: some View {
        Section {
            Toggle("Hotkey debug logging", isOn: $hotkeyDebugLoggingEnabled)
            Toggle("OpenAI debug logging", isOn: $openAIDebugLoggingEnabled)
        } header: {
            Text("Debug Logging")
        } footer: {
            Text("Enable temporary logs while diagnosing shortcut handling or OpenAI requests.")
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
    private func importConfiguration() {
        let previousLaunchAtLogin = managedSettings.launchAtLogin
        let previousShowInDock = managedSettings.showInDock
        let restoredSettings = viewModel.importConfiguration(appModel: appModel)

        if restoredSettings.launchAtLogin != previousLaunchAtLogin {
            suppressLaunchAtLoginChange = true
        }

        if restoredSettings.showInDock != previousShowInDock {
            suppressShowInDockChange = true
        }

        managedSettings = restoredSettings
    }

    private func handleLaunchAtLoginChange(oldValue: Bool, newValue: Bool) {
        guard hasLoadedManagedSettings else { return }

        if suppressLaunchAtLoginChange {
            suppressLaunchAtLoginChange = false
            return
        }

        let resolvedValue = viewModel.applyLaunchAtLoginChange(
            oldValue: oldValue,
            newValue: newValue,
            appModel: appModel
        )

        if resolvedValue != newValue {
            suppressLaunchAtLoginChange = true
            managedSettings.launchAtLogin = resolvedValue
        }
    }

    private func handleShowInDockChange(_ newValue: Bool) {
        guard hasLoadedManagedSettings else { return }

        if suppressShowInDockChange {
            suppressShowInDockChange = false
            return
        }

        viewModel.applyDockVisibilityChange(newValue, appModel: appModel)
    }
}
#endif
