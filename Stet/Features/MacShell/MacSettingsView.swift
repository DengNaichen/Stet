#if os(macOS)
import SwiftUI

private enum MacSettingsTab: String, CaseIterable, Identifiable, Hashable {
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
    @State private var selectedTab: MacSettingsTab? = .general

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                ForEach(MacSettingsTab.allCases) { tab in
                    sidebarLabel(for: tab)
                        .tag(tab)
                        .contentShape(Rectangle())
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 180, idealWidth: 200, maxWidth: 220)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(activeTab.title)
                        .font(.title3.weight(.semibold))

                    selectedContent
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
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

    @ViewBuilder
    private func sidebarLabel(for tab: MacSettingsTab) -> some View {
        if tab == .permissions, hasPermissionIssues {
            Label {
                Text(tab.title)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        } else {
            Label(tab.title, systemImage: tab.iconName)
        }
    }

    private var activeTab: MacSettingsTab {
        selectedTab ?? .general
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch activeTab {
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
        MacHotkeySettingsView()
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
        MacPermissionsSettingsView()
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
}
#endif
