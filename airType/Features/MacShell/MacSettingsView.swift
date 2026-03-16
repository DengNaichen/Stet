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
    @AppStorage(MacPreferences.rewriteEnabled) private var rewriteEnabled = false
    @AppStorage(MacPreferences.openAIBaseURL) private var openAIBaseURL = "https://api.openai.com/v1"
    @AppStorage(MacPreferences.translationTargetLanguage) private var translationTargetLanguageRawValue = TranslationTargetLanguage.english.rawValue
    @AppStorage(MacPreferences.translateSelectedTextOnTranslationHotkey) private var translateSelectedTextOnTranslationHotkey = true
    @AppStorage(MacPreferences.openAITranslationModel) private var openAITranslationModel = "gpt-5-mini"

    @StateObject private var dictionaryViewModel = DictionaryViewModel()
    @StateObject private var openAISettingsViewModel = MacOpenAISettingsViewModel()
    @State private var selectedTab: MacSettingsTab = .general
    @State private var hotkeyMessage: String?
    @State private var hotkeyMessageIsError = false

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
        }
        .onAppear {
            appModel.settingsDidAppear()
        }
        .onDisappear {
            appModel.settingsDidDisappear()
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
        MacGeneralSettingsView()
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

    private var hasPermissionIssues: Bool {
        appModel.microphoneAccessNeedsAttention ||
            appModel.autoPasteAccessNeedsAttention ||
            appModel.inputMonitoringNeedsAttention
    }

    private var translationTargetLanguageBinding: Binding<TranslationTargetLanguage> {
        Binding(
            get: { translationTargetLanguage },
            set: { translationTargetLanguageRawValue = $0.rawValue }
        )
    }

    private func reloadStateFromPreferences() {
        openAISettingsViewModel.load()
        dictionaryViewModel.load()
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
