#if os(macOS)
import AppKit
import SwiftUI

private enum MacSettingsTab: String, CaseIterable, Identifiable {
    case general
    case hotkey
    case openAI
    case dictionary
    case appBranch
    case history
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
        case .appBranch:
            return "App Branch"
        case .history:
            return "History"
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
        case .appBranch:
            return "square.stack.3d.up"
        case .history:
            return "clock.arrow.circlepath"
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
    @AppStorage(MacPreferences.historyRetentionPeriod) private var historyRetentionPeriodRawValue = HistoryRetentionPeriod.thirtyDays.rawValue
    @AppStorage(MacPreferences.interactionSoundsEnabled) private var interactionSoundsEnabled = true
    @AppStorage(MacPreferences.interactionSoundPreset) private var interactionSoundPresetRawValue = InteractionSoundPreset.soft.rawValue
    @AppStorage(MacPreferences.appBranchEnabled) private var appBranchEnabled = false
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
    @State private var selectedTab: MacSettingsTab = .general
    @State private var openAIAPIKey = ""
    @State private var openAIKeyMessage = "Stored securely in Keychain."
    @State private var openAIKeyMessageIsError = false
    @State private var hotkeyMessage: String?
    @State private var hotkeyMessageIsError = false
    @State private var generalMessage: String?
    @State private var generalMessageIsError = false
    @State private var inputDevices: [AudioInputDevice] = []
    @State private var appBranchRules: [AppBranchRule] = []
    @State private var editingRuleID: UUID?
    @State private var ruleNameDraft = ""
    @State private var rulePromptDraft = ""
    @State private var rulePromptDeliveryDraft: AppBranchPromptDelivery = .userMessage
    @State private var ruleAppsDraft = ""
    @State private var ruleURLsDraft = ""
    @State private var appBranchMessage: String?
    @State private var appBranchMessageIsError = false
    @State private var automationStates: [String: BrowserAutomationState] = [:]
    @State private var automationMessages: [String: String] = [:]
    @State private var automationLoadingTargets: Set<String> = []
    @State private var historyDisplayLimit = 20
    @State private var inspectedHistoryRecordID: UUID?

    private let settingsStore = DictationSettingsStore()
    private let browserTargets = BrowserURLReader.builtInTargets()

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
            refreshAutomationStates()
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
        .onChange(of: appBranchEnabled) { _, _ in
            refreshAutomationStates()
        }
        .onChange(of: historyRetentionPeriodRawValue) { _, _ in
            historyDisplayLimit = 20
            inspectedHistoryRecordID = nil
            appModel.refreshHistory()
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
        case .appBranch:
            appBranchTab
        case .history:
            historyTab
        case .permissions:
            permissionsTab
        }
    }

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsCard(
                title: "Configuration",
                description: "Export or import your current hotkey, prompt routing, dictionary, and behavior settings."
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
                description: "Enable temporary logs while diagnosing shortcut handling or prompt routing."
            ) {
                Toggle("Hotkey debug logging", isOn: $hotkeyDebugLoggingEnabled)
                Toggle("OpenAI and App Branch debug logging", isOn: $openAIDebugLoggingEnabled)
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
        settingsCard(
            title: "OpenAI Pipeline",
            description: "Configure the OpenAI-compatible transcription, translation, and rewrite path. Use the default OpenAI URL for direct BYOK, or point to your managed relay base URL."
        ) {
            settingsValueRow(title: "Transcription") {
                statusBadge(appModel.transcriptionProviderName, tint: .blue)
            }

            Toggle("Rewrite final transcript with OpenAI", isOn: $rewriteEnabled)
            Toggle(
                "Translate selected text directly when the translation shortcut is used",
                isOn: $translateSelectedTextOnTranslationHotkey
            )

            settingsValueRow(title: "Target language") {
                Picker("Target language", selection: translationTargetLanguageBinding) {
                    ForEach(TranslationTargetLanguage.allCases) { language in
                        Text(language.title).tag(language)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 220, alignment: .trailing)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Translation model")
                    .foregroundStyle(.secondary)

                TextField("OpenAI model for translation", text: $openAITranslationModel)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            }

            settingsValueRow(title: "Status") {
                statusBadge(
                    appModel.openAIStatusText,
                    tint: appModel.openAIStatusText == "Configured" ? .green : .orange
                )
            }

            settingsValueRow(title: "Rewrite") {
                statusBadge(
                    appModel.rewriteStatusText,
                    tint: rewriteEnabled ? .blue : .gray
                )
            }

            settingsValueRow(title: "Translation") {
                statusBadge(
                    translationTargetLanguage.title,
                    tint: .blue
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("OpenAI-compatible base URL")
                    .foregroundStyle(.secondary)

                TextField("https://api.openai.com/v1", text: $openAIBaseURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            }

            HStack(spacing: 8) {
                Button("Use OpenAI Default URL") {
                    openAIBaseURL = "https://api.openai.com/v1"
                }

                Button("Use Local Relay URL") {
                    openAIBaseURL = "http://127.0.0.1:54321/functions/v1/relay/v1"
                }
            }
            .controlSize(.small)

            VStack(alignment: .leading, spacing: 8) {
                Text("OpenAI API key")
                    .foregroundStyle(.secondary)

                SecureField("OpenAI API key or managed access token", text: $openAIAPIKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            }

            HStack(spacing: 8) {
                Button("Save Key") {
                    saveOpenAIAPIKey()
                }

                Button("Clear Key", role: .destructive) {
                    clearOpenAIAPIKey()
                }
            }
            .controlSize(.regular)

            if shouldHighlightMissingOpenAIKey {
                Text("Add an OpenAI API key or managed access token before using cloud transcription, translation, or rewrite.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Text(openAIKeyMessage)
                .font(.caption)
                .foregroundStyle(openAIKeyMessageIsError ? .red : .secondary)
        }
    }

    private var dictionaryTab: some View {
        DictionaryView(viewModel: dictionaryViewModel)
    }

    private var appBranchTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsCard(
                title: "Context Routing",
                description: "Switch OpenAI prompt guidance automatically based on the frontmost app or the current browser URL."
            ) {
                Toggle("Enable App Branch prompt routing", isOn: $appBranchEnabled)

                Text("URL matching is checked before app matching. Browser URL routing requires macOS Automation permission for the target browser.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            settingsCard(
                title: editingRuleID == nil ? "Create Rule" : "Edit Rule",
                description: "Use app bundle identifiers, wildcard URL patterns like github.com/*, choose how the prompt is delivered, and reuse supported template variables."
            ) {
                TextField("Rule name", text: $ruleNameDraft)
                    .textFieldStyle(.roundedBorder)

                settingsValueRow(title: "Delivery") {
                    Picker("Delivery", selection: $rulePromptDeliveryDraft) {
                        ForEach(AppBranchPromptDelivery.allCases) { delivery in
                            Text(delivery.title).tag(delivery)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 220, alignment: .trailing)
                }

                TextEditor(text: $rulePromptDraft)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .frame(minHeight: 120)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    )

                TextField("Bundle IDs, comma or newline separated", text: $ruleAppsDraft)
                    .textFieldStyle(.roundedBorder)

                TextField("URL patterns, comma or newline separated", text: $ruleURLsDraft)
                    .textFieldStyle(.roundedBorder)

                Text("Available variables: {{RAW_TRANSCRIPTION}}, {{TEXT}}, {{SELECTED_TEXT}}, {{TARGET_LANGUAGE}}, {{APP_NAME}}, {{BUNDLE_ID}}, {{URL}}")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Button("Add Frontmost App") {
                        appendFrontmostAppToDraft()
                    }

                    Spacer()

                    if editingRuleID != nil {
                        Button("Cancel") {
                            clearRuleDrafts()
                        }
                    }

                    Button(editingRuleID == nil ? "Save Rule" : "Update Rule") {
                        saveAppBranchRule()
                    }
                    .disabled(rulePromptDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if let appBranchMessage {
                    Text(appBranchMessage)
                        .font(.caption)
                        .foregroundStyle(appBranchMessageIsError ? .red : .secondary)
                }
            }

            settingsCard(
                title: "Rules",
                description: appBranchRules.isEmpty ? "No App Branch rules yet." : nil
            ) {
                if appBranchRules.isEmpty {
                    Text("Create your first rule above to bias OpenAI output toward a coding app, a chat app, or a specific website.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(appBranchRules) { rule in
                        appBranchRuleCard(rule)
                    }
                }
            }
        }
    }

    private var historyTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsCard(
                title: "Retention",
                description: "History stays local to this Mac. Older entries are trimmed automatically based on this retention window."
            ) {
                settingsValueRow(title: "Keep") {
                    Picker("Keep", selection: historyRetentionPeriodBinding) {
                        ForEach(HistoryRetentionPeriod.allCases) { retentionPeriod in
                            Text(retentionPeriod.title).tag(retentionPeriod)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 180, alignment: .trailing)
                }

                Text("Current entries: \(appModel.historyCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            settingsCard(
                title: "Recent Captures",
                description: "Copy, inspect, or delete recent dictation, translation, and rewrite results."
            ) {
                if appModel.hasHistory {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(appModel.allHistory.prefix(historyDisplayLimit))) { record in
                                historyRow(for: record)
                            }

                            if appModel.historyCount > historyDisplayLimit {
                                Button("Load More") {
                                    historyDisplayLimit += 20
                                }
                                .controlSize(.small)
                                .padding(.top, 4)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(minHeight: 240, maxHeight: 420)

                    Button("Clear Recent History", role: .destructive) {
                        appModel.clearHistory()
                    }
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                } else {
                    Text("Recent dictation captures will appear here after you finish recording.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                }
            }
        }
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

            if appBranchEnabled {
                settingsCard(
                    title: "Browser Automation",
                    description: "Grant browser automation permission so airType can read active-tab URLs for App Branch matching."
                ) {
                    ForEach(browserTargets) { target in
                        browserAutomationRow(target)
                    }

                    Button("Open Automation Settings") {
                        openAutomationSettings()
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    private var historyRetentionPeriod: HistoryRetentionPeriod {
        HistoryRetentionPeriod(rawValue: historyRetentionPeriodRawValue) ?? .thirtyDays
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

    private var shouldHighlightMissingOpenAIKey: Bool {
        openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

    private var historyRetentionPeriodBinding: Binding<HistoryRetentionPeriod> {
        Binding(
            get: { historyRetentionPeriod },
            set: { historyRetentionPeriodRawValue = $0.rawValue }
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
        loadOpenAIAPIKey()
        dictionaryViewModel.load()
        appBranchRules = settingsStore.loadAppBranchRules()
        launchAtLogin = MacAppBehaviorController.launchAtLoginIsEnabled()
        historyDisplayLimit = 20
        inspectedHistoryRecordID = nil
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

    private func loadOpenAIAPIKey() {
        openAIAPIKey = settingsStore.loadOpenAIAPIKey()
        openAIKeyMessage = openAIAPIKey.isEmpty
            ? "Add a key or managed access token to enable cloud features."
            : "Credential is saved in Keychain."
        openAIKeyMessageIsError = false
    }

    private func saveOpenAIAPIKey() {
        do {
            try settingsStore.saveOpenAIAPIKey(openAIAPIKey)
            let trimmedKey = openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
            openAIAPIKey = trimmedKey
            openAIKeyMessage = trimmedKey.isEmpty
                ? "Credential removed from Keychain."
                : "Credential saved in Keychain."
            openAIKeyMessageIsError = false
        } catch {
            openAIKeyMessage = error.localizedDescription
            openAIKeyMessageIsError = true
        }
    }

    private func clearOpenAIAPIKey() {
        openAIAPIKey = ""
        saveOpenAIAPIKey()
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
            appModel.refreshHistory()
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

    private func appendFrontmostAppToDraft() {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleID = app.bundleIdentifier,
              bundleID != Bundle.main.bundleIdentifier else {
            appBranchMessage = "Bring another app to the front, then try again."
            appBranchMessageIsError = true
            return
        }

        let existing = parsedRuleApps.map(\.bundleID)
        guard !existing.contains(bundleID) else { return }

        let appended = (parsedRuleApps + [AppBranchAppTarget(bundleID: bundleID, displayName: app.localizedName ?? bundleID)])
            .map(\.bundleID)
            .joined(separator: ", ")

        ruleAppsDraft = appended
    }

    private var parsedRuleApps: [AppBranchAppTarget] {
        DictationSettingsStore.words(from: ruleAppsDraft).map { bundleID in
            AppBranchAppTarget(
                bundleID: bundleID,
                displayName: resolvedDisplayName(for: bundleID)
            )
        }
    }

    private var parsedRuleURLs: [String] {
        DictationSettingsStore.words(from: ruleURLsDraft).map(AppBranchRule.canonicalizeURLPattern)
    }

    private func resolvedDisplayName(for bundleID: String) -> String {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
              let bundle = Bundle(url: appURL) else {
            return bundleID
        }

        return (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: kCFBundleNameKey as String) as? String)
            ?? bundleID
    }

    private func saveAppBranchRule() {
        let trimmedName = ruleNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPrompt = rulePromptDraft.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedPrompt.isEmpty else {
            appBranchMessage = "Prompt instructions cannot be empty."
            appBranchMessageIsError = true
            return
        }

        guard !parsedRuleApps.isEmpty || !parsedRuleURLs.isEmpty else {
            appBranchMessage = "Add at least one app bundle identifier or one URL pattern."
            appBranchMessageIsError = true
            return
        }

        let rule = AppBranchRule(
            id: editingRuleID ?? UUID(),
            name: trimmedName.isEmpty ? "Untitled Rule" : trimmedName,
            prompt: trimmedPrompt,
            promptDelivery: rulePromptDeliveryDraft,
            appTargets: parsedRuleApps,
            urlPatterns: parsedRuleURLs,
            isEnabled: true
        )

        if let editingRuleID,
           let index = appBranchRules.firstIndex(where: { $0.id == editingRuleID }) {
            appBranchRules[index] = rule
            appBranchMessage = "Updated App Branch rule."
        } else {
            appBranchRules.append(rule)
            appBranchMessage = "Created App Branch rule."
        }

        appBranchRules.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        settingsStore.saveAppBranchRules(appBranchRules)
        appBranchMessageIsError = false
        clearRuleDrafts()
    }

    private func beginEditing(_ rule: AppBranchRule) {
        editingRuleID = rule.id
        ruleNameDraft = rule.name
        rulePromptDraft = rule.prompt
        rulePromptDeliveryDraft = rule.promptDelivery
        ruleAppsDraft = rule.appTargets.map(\.bundleID).joined(separator: ", ")
        ruleURLsDraft = rule.urlPatterns.joined(separator: ", ")
        appBranchMessage = nil
    }

    private func deleteRule(_ rule: AppBranchRule) {
        appBranchRules.removeAll { $0.id == rule.id }
        settingsStore.saveAppBranchRules(appBranchRules)

        if editingRuleID == rule.id {
            clearRuleDrafts()
        }
    }

    private func clearRuleDrafts() {
        editingRuleID = nil
        ruleNameDraft = ""
        rulePromptDraft = ""
        rulePromptDeliveryDraft = .userMessage
        ruleAppsDraft = ""
        ruleURLsDraft = ""
    }

    private func refreshAutomationStates() {
        for target in browserTargets {
            automationStates[target.bundleID] = BrowserURLReader.browserAutomationState(for: target.bundleID)
        }
    }

    private func requestAutomationPermission(for target: BrowserAutomationTarget) {
        automationLoadingTargets.insert(target.bundleID)

        Task { @MainActor in
            let state = BrowserURLReader.requestAutomationPermission(for: target.bundleID)
            automationStates[target.bundleID] = state
            automationMessages[target.bundleID] = state == .enabled ? "Authorization granted." : "Authorization not granted."
            automationLoadingTargets.remove(target.bundleID)
        }
    }

    private func testAutomation(for target: BrowserAutomationTarget) {
        automationLoadingTargets.insert(target.bundleID)

        Task { @MainActor in
            let result = BrowserURLReader.testURLRead(for: target.bundleID)
            if let url = result.url, !url.isEmpty {
                automationStates[target.bundleID] = .enabled
                automationMessages[target.bundleID] = "Browser URL read test succeeded."
            } else if result.permissionDenied {
                automationStates[target.bundleID] = .disabled
                automationMessages[target.bundleID] = "Browser URL read test failed: permission denied."
            } else if result.appNotRunning {
                automationMessages[target.bundleID] = "Browser URL read test failed: browser is not running."
            } else if let errorCode = result.lastErrorCode {
                automationMessages[target.bundleID] = "Browser URL read test failed (error: \(errorCode))."
            } else {
                automationMessages[target.bundleID] = "Browser URL read test failed."
            }

            automationLoadingTargets.remove(target.bundleID)
        }
    }

    private func openAutomationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    private func appBranchRuleCard(_ rule: AppBranchRule) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(rule.name)
                    .font(.headline)

                Spacer()

                statusBadge(rule.promptDelivery.title, tint: rule.promptDelivery == .systemPrompt ? .blue : .green)

                Button("Edit") {
                    beginEditing(rule)
                }
                .controlSize(.small)

                Button("Delete", role: .destructive) {
                    deleteRule(rule)
                }
                .controlSize(.small)
            }

            Text(rule.prompt)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)

            if !rule.appTargets.isEmpty {
                Text("Apps: " + rule.appTargets.map(\.displayName).joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !rule.urlPatterns.isEmpty {
                Text("URLs: " + rule.urlPatterns.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    private func browserAutomationRow(_ target: BrowserAutomationTarget) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(target.displayName)
                    .font(.subheadline)

                if let message = automationMessages[target.bundleID] {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Read the current active-tab URL from \(target.displayName).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if automationLoadingTargets.contains(target.bundleID) {
                ProgressView()
                    .controlSize(.small)
            }

            statusBadge(
                automationStates[target.bundleID] == .enabled ? "Enabled" : "Disabled",
                tint: automationStates[target.bundleID] == .enabled ? .green : .orange
            )

            Button("Request") {
                requestAutomationPermission(for: target)
            }
            .controlSize(.small)

            Button("Test") {
                testAutomation(for: target)
            }
            .controlSize(.small)
        }
        .padding(.vertical, 2)
    }

    private func historyRow(for record: TranscriptionRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 8) {
                    statusBadge(historyBadgeTitle(for: record), tint: historyBadgeTint(for: record))

                    Text(timestampString(for: record.createdAt))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                HStack(spacing: 8) {
                    Button("Details") {
                        inspectedHistoryRecordID = record.id
                    }
                    .controlSize(.small)

                    Button(appModel.didCopyRecord(record) ? "Copied" : "Copy") {
                        appModel.copyToClipboard(record: record)
                    }
                    .controlSize(.small)

                    Button("Delete", role: .destructive) {
                        appModel.deleteHistoryRecord(record)
                    }
                    .controlSize(.small)
                }
            }

            Text(record.text)
                .textSelection(.enabled)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                Text(record.metadata.source.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let focusedAppName = record.metadata.focusedAppName, !focusedAppName.isEmpty {
                    Text("App: \(focusedAppName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let matchedRule = record.metadata.matchedAppBranchRuleName, !matchedRule.isEmpty {
                    Text("Rule: \(matchedRule)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if inspectedHistoryRecordID == record.id {
                historyMetadataDetails(for: record)
            }

            Divider()
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

    private func timestampString(for date: Date) -> String {
        Self.timestampFormatter.string(from: date)
    }

    private func historyBadgeTitle(for record: TranscriptionRecord) -> String {
        record.metadata.kind.title
    }

    private func historyBadgeTint(for record: TranscriptionRecord) -> Color {
        switch record.metadata.kind {
        case .dictation:
            return .blue
        case .translation:
            return .green
        case .rewrite:
            return .orange
        }
    }

    @ViewBuilder
    private func historyMetadataDetails(for record: TranscriptionRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            metadataLine("Source", record.metadata.source.title)
            metadataLine("Provider", record.metadata.transcriptionProvider)
            metadataLine("Transcription Model", record.metadata.transcriptionModel)
            metadataLine("Translation Model", record.metadata.translationModel)
            metadataLine("Rewrite Model", record.metadata.rewriteModel)
            metadataLine("Target Language", record.metadata.targetLanguage)
            metadataLine("Focused App", record.metadata.focusedAppName)
            metadataLine("Bundle ID", record.metadata.focusedBundleID)
            metadataLine("App Branch Rule", record.metadata.matchedAppBranchRuleName)
            metadataLine("Matched URL Pattern", record.metadata.matchedURLPattern)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.secondary.opacity(0.06))
        )
    }

    @ViewBuilder
    private func metadataLine(_ title: String, _ value: String?) -> some View {
        let trimmedValue = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedValue.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 132, alignment: .leading)
                Text(trimmedValue)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
            }
        }
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
#endif
