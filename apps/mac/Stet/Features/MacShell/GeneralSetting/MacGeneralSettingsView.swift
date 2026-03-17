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
        VStack(alignment: .leading, spacing: 16) {
            configurationSection
            audioSection
            captureSection
            interactionSoundsSection
            appBehaviorSection
            updatesSection
            debugLoggingSection
            feedbackView
        }
        .toggleStyle(.switch)
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
        settingsCard(
            title: "Configuration",
            description: "Export or import your current hotkey, dictionary, and behavior settings."
        ) {
            HStack(spacing: 8) {
                Button("Export Configuration") {
                    viewModel.exportConfiguration()
                }

                Button("Import Configuration") {
                    importConfiguration()
                }
            }
        }
    }

    private var audioSection: some View {
        settingsCard(
            title: "Microphone",
        ) {
            settingsValueRow(title: "Microphone") {
                Picker("Microphone", selection: selectedAudioInputDeviceIDBinding) {
                    Text(viewModel.systemDefaultInputDeviceLabel).tag(0)

                    ForEach(viewModel.inputDevices) { device in
                        Text(device.name).tag(Int(device.id))
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 240, alignment: .trailing)
            }
        }
    }

    private var captureSection: some View {
        settingsCard(
            title: "Capture",
            description: "Pause external media automatically while dictation is active."
        ) {
            Toggle("Pause media during dictation and resume afterward", isOn: $pauseMediaDuringDictation)
        }
    }

    private var interactionSoundsSection: some View {
        settingsCard(
            title: "Interaction Sounds",
        ) {
            Toggle("Enable interaction sounds", isOn: $interactionSoundsEnabled)
        }
    }

    private var appBehaviorSection: some View {
        settingsCard(
            title: "App Behavior",
        ) {
            Toggle("Launch at Login", isOn: $managedSettings.launchAtLogin)
            Toggle("Show in Dock", isOn: $managedSettings.showInDock)
        }
    }

    private var updatesSection: some View {
        settingsCard(
            title: "Updates",
            description: "Automatically check for app updates, or run a manual check at any time."
        ) {
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
        }
    }

    private var debugLoggingSection: some View {
        settingsCard(
            title: "Debug Logging",
            description: "Enable temporary logs while diagnosing shortcut handling or OpenAI requests."
        ) {
            Toggle("Hotkey debug logging", isOn: $hotkeyDebugLoggingEnabled)
            Toggle("OpenAI debug logging", isOn: $openAIDebugLoggingEnabled)
        }
    }

    @ViewBuilder
    private var feedbackView: some View {
        if let feedback = viewModel.feedback {
            Text(feedback.message)
                .font(.caption)
                .foregroundStyle(feedback.isError ? .red : .secondary)
                .padding(.horizontal, 4)
        }
    }

    private var selectedAudioInputDeviceIDBinding: Binding<Int> {
        Binding(
            get: { managedSettings.selectedAudioInputDeviceID },
            set: { newValue in
                managedSettings.selectedAudioInputDeviceID = newValue
                viewModel.persistSelectedAudioInputDeviceID(newValue)
            }
        )
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

    @ViewBuilder
    private func settingsCard<Content: View>(
        title: String,
        description: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.headline)

                if let description {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
    }

    @ViewBuilder
    private func settingsValueRow<Value: View>(
        title: String,
        @ViewBuilder value: () -> Value
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            value()
        }
    }
}
#endif
