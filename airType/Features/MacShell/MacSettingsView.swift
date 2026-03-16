#if os(macOS)
import AppKit
import SwiftUI

private enum MacSettingsTab: String, CaseIterable, Identifiable {
    case general
    case hotkey
    case openAI
    case dictionary
    case permissions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:
            return "General"
        case .hotkey:
            return "Hotkey"
        case .openAI:
            return "OpenAI"
        case .dictionary:
            return "Dictionary"
        case .permissions:
            return "Permissions"
        }
    }

    var iconName: String {
        switch self {
        case .general:
            return "slider.horizontal.3"
        case .hotkey:
            return "keyboard"
        case .openAI:
            return "key.horizontal"
        case .dictionary:
            return "text.book.closed"
        case .permissions:
            return "lock.shield"
        }
    }
}

struct MacSettingsView: View {
    @EnvironmentObject private var appModel: MacAppModel
    @EnvironmentObject private var appUpdateManager: AppUpdateManager
    @AppStorage(MacPreferences.showPanelOnLaunch) private var showPanelOnLaunch = false
    @AppStorage(MacPreferences.copyToClipboardOnCapture) private var copyToClipboardOnCapture = true
    @AppStorage(MacPreferences.autoPasteOnCapture) private var autoPasteOnCapture = true
    @AppStorage(MacPreferences.revealPanelOnCapture) private var revealPanelOnCapture = false
    @AppStorage(MacPreferences.pauseMediaDuringDictation) private var pauseMediaDuringDictation = false
    @AppStorage(MacPreferences.selectedAudioInputDeviceID) private var selectedAudioInputDeviceIDRaw = 0
    @AppStorage(MacPreferences.rewriteEnabled) private var rewriteEnabled = false
    @AppStorage(MacPreferences.openAIBaseURL) private var openAIBaseURL = "https://api.openai.com/v1"
    @AppStorage(MacPreferences.translationTargetLanguage) private var translationTargetLanguageRawValue = TranslationTargetLanguage.english.rawValue
    @AppStorage(MacPreferences.translateSelectedTextOnTranslationHotkey) private var translateSelectedTextOnTranslationHotkey = true
    @AppStorage(MacPreferences.openAITranslationModel) private var openAITranslationModel = "gpt-5-mini"
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
    @AppStorage(MacPreferences.hotkeyDistinguishModifierSides) private var hotkeyDistinguishModifierSides = false

    @StateObject private var dictionaryViewModel = DictionaryViewModel()
    @StateObject private var openAISettingsViewModel = MacOpenAISettingsViewModel()
    @State private var selectedTab: MacSettingsTab = .general
    @State private var hotkeyMessage: String?
    @State private var hotkeyMessageIsError = false
    @State private var generalMessage: String?
    @State private var generalMessageIsError = false
    @State private var inputDevices: [AudioInputDevice] = []

    private let settingsStore = DictationSettingsStore()

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))

            HStack(alignment: .top, spacing: 8) {
                sidebar
                    .frame(width: 184)
                    .frame(maxHeight: .infinity, alignment: .top)

                VStack(alignment: .leading, spacing: 12) {
                    Text(selectedTab.title)
                        .font(.title3.weight(.semibold))
                        .padding(.horizontal, 8)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            tabContent
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(.horizontal, 8)
                        .padding(.top, 2)
                        .padding(.bottom, 10)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
            .padding(.top, 10)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .frame(minWidth: 860, minHeight: 760)
        .task {
            reloadStateFromPreferences()
            refreshInputDevices()
        }
        .onAppear {
            appModel.settingsDidAppear()
        }
        .onDisappear {
            appModel.settingsDidDisappear()
        }
        .onChange(of: launchAtLogin) { oldValue, newValue in
            guard oldValue != newValue else { return }
            applyLaunchAtLogin(enabled: newValue, fallback: oldValue)
        }
        .onChange(of: showInDock) { _, newValue in
            appModel.applyDockVisibility(showInDock: newValue)
            generalMessage = newValue ? "Dock icon enabled." : "Dock icon hidden."
            generalMessageIsError = false
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 10, height: 10)

                VStack(alignment: .leading, spacing: 1) {
                    Text("airType")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                    Text("Settings")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 12)
            .padding(.bottom, 6)

            ForEach(MacSettingsTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: tab.iconName)
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 16)
                        Text(tab.title)
                            .font(.system(size: 13, weight: .medium))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(tab == selectedTab ? .white : .primary)
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(tab == selectedTab ? Color.accentColor : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 8)

            if hasPermissionIssues {
                Button {
                    selectedTab = .permissions
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.orange)
                        Text("Attention Needed")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.orange)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.orange.opacity(0.10))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.orange.opacity(0.35), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
        .padding(.top, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.72))
        )
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .general:
            generalTab
        case .hotkey:
            hotkeyTab
        case .openAI:
            openAITab
        case .dictionary:
            dictionaryTab
        case .permissions:
            permissionsTab
        }
    }

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsCard(
                title: "Configuration",
                description: "Export or import your current hotkey, dictionary, and behavior settings."
            ) {
                HStack(spacing: 8) {
                    Button("Export Configuration") {
                        exportConfiguration()
                    }

                    Button("Import Configuration") {
                        importConfiguration()
                    }
                }

                if let generalMessage {
                    Text(generalMessage)
                        .font(.caption)
                        .foregroundStyle(generalMessageIsError ? .red : .secondary)
                }
            }

            settingsCard(
                title: "Audio",
                description: "Choose which microphone airType should use on the next recording session."
            ) {
                settingsValueRow(title: "Microphone") {
                    Picker("Microphone", selection: $selectedAudioInputDeviceIDRaw) {
                        Text(systemDefaultInputDeviceLabel).tag(0)

                        ForEach(inputDevices) { device in
                            Text(device.name).tag(Int(device.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 240, alignment: .trailing)
                }

                HStack(spacing: 8) {
                    Button("Refresh Devices") {
                        refreshInputDevices()
                    }
                    .controlSize(.small)

                    if let selectedAudioInputDeviceSummary {
                        Text(selectedAudioInputDeviceSummary)
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
                    appModel.previewInteractionSound(interactionSoundPreset)
                }
                .controlSize(.small)
            }

            settingsCard(
                title: "App Behavior",
                description: "Control whether airType starts with macOS and whether it appears in the Dock."
            ) {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                Toggle("Show in Dock", isOn: $showInDock)

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
    }

    private var hotkeyTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            MacHotKeySettingsSectionView(hotkey: .dictation) { shortcut in
                hotkeyMessage = shortcut.map { "Shortcut updated to \($0)." } ?? "Shortcut cleared."
                hotkeyMessageIsError = false
            }

            if let hotkeyMessage {
                Text(hotkeyMessage)
                    .font(.caption)
                    .foregroundStyle(hotkeyMessageIsError ? .red : .secondary)
            }
        }
    }

    private var openAITab: some View {
        MacOpenAISettingsView(
            viewModel: openAISettingsViewModel,
            rewriteEnabled: $rewriteEnabled,
            openAIBaseURL: $openAIBaseURL,
            translationTargetLanguage: translationTargetLanguageBinding,
            translateSelectedTextOnTranslationHotkey: $translateSelectedTextOnTranslationHotkey,
            openAITranslationModel: $openAITranslationModel
        )
    }

    private var dictionaryTab: some View {
        DictionaryView(viewModel: dictionaryViewModel)
    }

    private var permissionsTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsCard(
                title: "Core Permissions",
                description: "airType uses separate permissions for capture, hotkeys, and writing text back into other apps."
            ) {
                permissionRow(
                    title: "Microphone",
                    detail: "Required to capture audio for dictation.",
                    statusText: appModel.microphoneAccessStatusText,
                    tint: appModel.microphoneAccessNeedsAttention ? .orange : .green
                ) {
                    Button("Open Settings") {
                        appModel.openMicrophoneSettings()
                    }
                }

                permissionRow(
                    title: "Speech Recognition",
                    detail: "The current on-device speech path does not require the legacy Speech Recognition permission.",
                    statusText: appModel.speechRecognitionStatusText,
                    tint: .gray
                ) {
                    EmptyView()
                }

                permissionRow(
                    title: "Text Injection",
                    detail: "Accessibility helps read selected text directly. Input injection is used to paste captured text back into other apps automatically.",
                    statusText: appModel.autoPasteStatusText,
                    tint: appModel.autoPasteAccessNeedsAttention ? .orange : .green
                ) {
                    Button("Request Access") {
                        appModel.requestAutoPasteAccess()
                    }

                    Button("Open Settings") {
                        appModel.openAccessibilitySettings()
                    }
                }

                permissionRow(
                    title: "Input Monitoring",
                    detail: "Required for modifier-only shortcuts like fn and for the event-tap hotkey backend.",
                    statusText: appModel.inputMonitoringStatusText,
                    tint: appModel.inputMonitoringNeedsAttention ? .orange : .green
                ) {
                    Button("Request Access") {
                        appModel.requestInputMonitoringAccess()
                    }

                    Button("Open Settings") {
                        appModel.openInputMonitoringSettings()
                    }
                }
            }
        }
    }

    private var translationTargetLanguage: TranslationTargetLanguage {
        TranslationTargetLanguage(rawValue: translationTargetLanguageRawValue) ?? .english
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

    private var hasPermissionIssues: Bool {
        appModel.microphoneAccessNeedsAttention ||
            appModel.autoPasteAccessNeedsAttention ||
            appModel.inputMonitoringNeedsAttention
    }

    private var interactionSoundPresetBinding: Binding<InteractionSoundPreset> {
        Binding(
            get: { interactionSoundPreset },
            set: { interactionSoundPresetRawValue = $0.rawValue }
        )
    }

    private var translationTargetLanguageBinding: Binding<TranslationTargetLanguage> {
        Binding(
            get: { translationTargetLanguage },
            set: { translationTargetLanguageRawValue = $0.rawValue }
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

    private func reloadStateFromPreferences() {
        openAISettingsViewModel.load()
        dictionaryViewModel.load()
        launchAtLogin = MacAppBehaviorController.launchAtLoginIsEnabled()
        refreshInputDevices()
    }

    private var systemDefaultInputDeviceLabel: String {
        if let defaultDeviceID = AudioInputDeviceManager.defaultInputDeviceID(),
           let device = inputDevices.first(where: { $0.id == defaultDeviceID }) {
            return "System Default (\(device.name))"
        }

        return "System Default"
    }

    private var selectedAudioInputDeviceSummary: String? {
        if selectedAudioInputDeviceIDRaw == 0 {
            return AudioInputDeviceManager.defaultInputDeviceID()
                .flatMap { defaultDeviceID in
                    inputDevices.first(where: { $0.id == defaultDeviceID })?.name
                }
                .map { "Currently resolves to \($0)." }
        }

        if let selectedDevice = inputDevices.first(where: { Int($0.id) == selectedAudioInputDeviceIDRaw }) {
            return "Using \(selectedDevice.name) on the next capture."
        }

        return "The selected input device is unavailable. Refresh or switch back to System Default."
    }

    private func refreshInputDevices() {
        inputDevices = AudioInputDeviceManager.availableInputDevices()

        if inputDevices.isEmpty {
            selectedAudioInputDeviceIDRaw = 0
            return
        }

        let selectionExists = selectedAudioInputDeviceIDRaw == 0 ||
            inputDevices.contains(where: { Int($0.id) == selectedAudioInputDeviceIDRaw })

        if !selectionExists {
            selectedAudioInputDeviceIDRaw = 0
        }
    }

    private func exportConfiguration() {
        do {
            try MacConfigurationTransferManager.exportConfiguration(using: settingsStore)
            generalMessage = "Configuration exported."
            generalMessageIsError = false
        } catch {
            generalMessage = error.localizedDescription
            generalMessageIsError = true
        }
    }

    private func importConfiguration() {
        do {
            try MacConfigurationTransferManager.importConfiguration(using: settingsStore)
            reloadStateFromPreferences()
            try? appModel.setLaunchAtLoginEnabled(launchAtLogin)
            appModel.refreshRuntimeFromSettings()
            generalMessage = "Configuration imported. API keys are still managed separately in Keychain."
            generalMessageIsError = false
        } catch {
            generalMessage = error.localizedDescription
            generalMessageIsError = true
        }
    }

    private func applyLaunchAtLogin(enabled: Bool, fallback: Bool) {
        do {
            try appModel.setLaunchAtLoginEnabled(enabled)
            generalMessage = enabled ? "Launch at Login enabled." : "Launch at Login disabled."
            generalMessageIsError = false
        } catch {
            launchAtLogin = fallback
            generalMessage = error.localizedDescription
            generalMessageIsError = true
        }
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

    @ViewBuilder
    private func permissionRow<Actions: View>(
        title: String,
        detail: String,
        statusText: String,
        tint: Color,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            statusBadge(statusText, tint: tint)
            actions()
        }
        .padding(.vertical, 2)
    }

}
#endif
