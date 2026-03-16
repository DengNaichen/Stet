#if os(macOS)
import AppKit
import SwiftUI

struct MacGeneralSettingsView: View {
    @EnvironmentObject private var appModel: MacAppModel
    @EnvironmentObject private var appUpdateManager: AppUpdateManager

    @AppStorage(MacPreferences.showPanelOnLaunch) private var showPanelOnLaunch = false
    @AppStorage(MacPreferences.copyToClipboardOnCapture) private var copyToClipboardOnCapture = true
    @AppStorage(MacPreferences.autoPasteOnCapture) private var autoPasteOnCapture = true
    @AppStorage(MacPreferences.revealPanelOnCapture) private var revealPanelOnCapture = false
    @AppStorage(MacPreferences.pauseMediaDuringDictation) private var pauseMediaDuringDictation = false
    @AppStorage(MacPreferences.selectedAudioInputDeviceID) private var selectedAudioInputDeviceIDRaw = 0
    @AppStorage(MacPreferences.interactionSoundsEnabled) private var interactionSoundsEnabled = true
    @AppStorage(MacPreferences.interactionSoundPreset) private var interactionSoundPresetRawValue = InteractionSoundPreset.soft.rawValue
    @AppStorage(MacPreferences.launchAtLogin) private var launchAtLogin = false
    @AppStorage(MacPreferences.showInDock) private var showInDock = false
    @AppStorage(MacPreferences.proxyMode) private var proxyModeRawValue = NetworkProxyMode.system.rawValue
    @AppStorage(MacPreferences.customProxyScheme) private var customProxySchemeRawValue = CustomProxyScheme.http.rawValue
    @AppStorage(MacPreferences.customProxyHost) private var customProxyHost = ""
    @AppStorage(MacPreferences.customProxyPort) private var customProxyPort = ""
    @AppStorage(MacPreferences.hotkeyDebugLoggingEnabled) private var hotkeyDebugLoggingEnabled = false
    @AppStorage(MacPreferences.openAIDebugLoggingEnabled) private var openAIDebugLoggingEnabled = false

    @StateObject private var viewModel = MacGeneralSettingsViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsCard(
                title: "Configuration",
                description: "Export or import your current hotkey, dictionary, and behavior settings."
            ) {
                HStack(spacing: 8) {
                    Button("Export Configuration") {
                        viewModel.exportConfiguration()
                    }

                    Button("Import Configuration") {
                        let restored = viewModel.importConfiguration(
                            appModel: appModel,
                            currentSelectedAudioInputDeviceID: selectedAudioInputDeviceIDRaw
                        )
                        launchAtLogin = restored.launchAtLogin
                        selectedAudioInputDeviceIDRaw = restored.selectedAudioInputDeviceID
                    }
                }

                if let message = viewModel.message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(viewModel.messageIsError ? .red : .secondary)
                }
            }

            settingsCard(
                title: "Audio",
                description: "Choose which microphone airType should use on the next recording session."
            ) {
                settingsValueRow(title: "Microphone") {
                    Picker("Microphone", selection: $selectedAudioInputDeviceIDRaw) {
                        Text(viewModel.systemDefaultInputDeviceLabel).tag(0)

                        ForEach(viewModel.inputDevices) { device in
                            Text(device.name).tag(Int(device.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 240, alignment: .trailing)
                }

                HStack(spacing: 8) {
                    Button("Refresh Devices") {
                        selectedAudioInputDeviceIDRaw = viewModel.refreshInputDevices(
                            selectedAudioInputDeviceID: selectedAudioInputDeviceIDRaw
                        )
                    }
                    .controlSize(.small)

                    if let summary = viewModel.selectedAudioInputDeviceSummary(for: selectedAudioInputDeviceIDRaw) {
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text("The selected microphone is applied the next time dictation starts. On macOS this now feeds both the on-device and OpenAI recording paths.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            settingsCard(
                title: "Output",
                description: "Control where dictation results go after capture finishes."
            ) {
                Toggle("Show dictation capsule on launch", isOn: $showPanelOnLaunch)
                Toggle("Copy final transcript automatically", isOn: $copyToClipboardOnCapture)
                Toggle("Paste transcript back into the previous app", isOn: $autoPasteOnCapture)
                Toggle("Keep the capsule visible when paste fails", isOn: $revealPanelOnCapture)
                Toggle("Pause media during dictation and resume afterward", isOn: $pauseMediaDuringDictation)
            }

            settingsCard(
                title: "Interaction Sounds",
                description: "Play a short start and finish cue around each dictation session."
            ) {
                Toggle("Enable interaction sounds", isOn: $interactionSoundsEnabled)

                settingsValueRow(title: "Preset") {
                    Picker("Preset", selection: interactionSoundPresetBinding) {
                        ForEach(InteractionSoundPreset.allCases) { preset in
                            Text(preset.title).tag(preset)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 180, alignment: .trailing)
                }

                Button("Try Sound") {
                    viewModel.previewInteractionSound(interactionSoundPreset, appModel: appModel)
                }
                .controlSize(.small)
            }

            settingsCard(
                title: "App Behavior",
                description: "Control whether airType starts with macOS and whether it appears in the Dock."
            ) {
                Toggle("Launch at Login", isOn: launchAtLoginBinding)
                Toggle("Show in Dock", isOn: showInDockBinding)

                Text("Dock visibility applies immediately. Launch at Login uses macOS app service registration.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            settingsCard(
                title: "Network",
                description: "Choose whether OpenAI requests follow the system proxy, bypass it, or use a custom endpoint."
            ) {
                settingsValueRow(title: "Proxy") {
                    Picker("Proxy", selection: proxyModeBinding) {
                        ForEach(NetworkProxyMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 180, alignment: .trailing)
                }

                if proxyMode == .custom {
                    settingsValueRow(title: "Scheme") {
                        Picker("Scheme", selection: customProxySchemeBinding) {
                            ForEach(CustomProxyScheme.allCases) { scheme in
                                Text(scheme.title).tag(scheme)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 180, alignment: .trailing)
                    }

                    TextField("Proxy host", text: $customProxyHost)
                        .textFieldStyle(.roundedBorder)

                    TextField("Proxy port", text: $customProxyPort)
                        .textFieldStyle(.roundedBorder)
                }
            }

            settingsCard(
                title: "Updates",
                description: "Sparkle checks your signed appcast feed and can download or install updates for distributed builds."
            ) {
                Toggle(
                    "Check for updates automatically",
                    isOn: Binding(
                        get: { appUpdateManager.automaticallyChecksForUpdates },
                        set: { appUpdateManager.setAutomaticallyChecksForUpdates($0) }
                    )
                )
                .disabled(!appUpdateManager.isConfigured)

                Toggle(
                    "Download and install updates automatically when possible",
                    isOn: Binding(
                        get: { appUpdateManager.automaticallyDownloadsUpdates },
                        set: { appUpdateManager.setAutomaticallyDownloadsUpdates($0) }
                    )
                )
                .disabled(!appUpdateManager.isConfigured)

                settingsValueRow(title: "Appcast") {
                    Text(appUpdateManager.configuredFeedURLString ?? "Missing")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(appUpdateManager.isConfigured ? Color.secondary : Color.orange)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 360, alignment: .trailing)
                }

                settingsValueRow(title: "Status") {
                    statusBadge(
                        appUpdateManager.statusLabel,
                        tint: Color(nsColor: appUpdateManager.statusTint)
                    )
                }

                if let detailText = appUpdateManager.detailText {
                    Text(detailText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    Button("Check Now") {
                        appUpdateManager.checkForUpdates()
                    }
                    .disabled(appUpdateManager.isChecking || !appUpdateManager.canCheckForUpdates)
                }

                Text("Set SPARKLE_FEED_URL and SPARKLE_PUBLIC_ED_KEY in the build settings before shipping a Sparkle-enabled build.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            settingsCard(
                title: "Debug Logging",
                description: "Enable temporary logs while diagnosing shortcut handling or OpenAI requests."
            ) {
                Toggle("Hotkey debug logging", isOn: $hotkeyDebugLoggingEnabled)
                Toggle("OpenAI debug logging", isOn: $openAIDebugLoggingEnabled)
            }
        }
        .task {
            let restored = viewModel.load(currentSelectedAudioInputDeviceID: selectedAudioInputDeviceIDRaw)
            launchAtLogin = restored.launchAtLogin
            selectedAudioInputDeviceIDRaw = restored.selectedAudioInputDeviceID
        }
    }

    private var interactionSoundPreset: InteractionSoundPreset {
        InteractionSoundPreset(rawValue: interactionSoundPresetRawValue) ?? .soft
    }

    private var proxyMode: NetworkProxyMode {
        NetworkProxyMode(rawValue: proxyModeRawValue) ?? .system
    }

    private var customProxyScheme: CustomProxyScheme {
        CustomProxyScheme(rawValue: customProxySchemeRawValue) ?? .http
    }

    private var interactionSoundPresetBinding: Binding<InteractionSoundPreset> {
        Binding(
            get: { interactionSoundPreset },
            set: { interactionSoundPresetRawValue = $0.rawValue }
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin },
            set: { newValue in
                let fallback = launchAtLogin
                launchAtLogin = viewModel.applyLaunchAtLoginChange(
                    oldValue: fallback,
                    newValue: newValue,
                    appModel: appModel
                )
            }
        )
    }

    private var showInDockBinding: Binding<Bool> {
        Binding(
            get: { showInDock },
            set: { newValue in
                showInDock = newValue
                viewModel.applyDockVisibilityChange(newValue, appModel: appModel)
            }
        )
    }

    private var proxyModeBinding: Binding<NetworkProxyMode> {
        Binding(
            get: { proxyMode },
            set: { proxyModeRawValue = $0.rawValue }
        )
    }

    private var customProxySchemeBinding: Binding<CustomProxyScheme> {
        Binding(
            get: { customProxyScheme },
            set: { customProxySchemeRawValue = $0.rawValue }
        )
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

    private func statusBadge(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.12))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(tint.opacity(0.22), lineWidth: 1)
            )
    }
}
#endif
