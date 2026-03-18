#if os(macOS)
import AppKit
import SwiftUI

struct MacGeneralSettingsView: View {
    @EnvironmentObject private var appModel: MacAppModel
    @EnvironmentObject private var appUpdateManager: AppUpdateManager

    @StateObject private var viewModel = MacGeneralSettingsViewModel()

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
            viewModel.configure(appModel: appModel, appUpdateManager: appUpdateManager)
            viewModel.load()
        }
    }

    private var configurationSection: some View {
        Section {
            HStack(spacing: 10) {
                Button("Export Configuration") {
                    viewModel.exportConfiguration()
                }

                Button("Import Configuration") {
                    viewModel.importConfiguration()
                }
            }
        } header: {
            Text("Configuration")
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
        } header: {
            Text("Interaction Sounds")
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

    private var debugLoggingSection: some View {
        Section {
            Toggle("Hotkey debug logging", isOn: $viewModel.hotkeyDebugLoggingEnabled)
            Toggle("OpenAI debug logging", isOn: $viewModel.openAIDebugLoggingEnabled)
        } header: {
            Text("Debug Logging")
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
