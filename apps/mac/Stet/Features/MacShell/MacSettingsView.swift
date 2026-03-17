#if os(macOS)
import SwiftUI

private enum MacSettingsSidebarGroup: String, CaseIterable, Identifiable {
    case workspace = "Workspace"
    case automation = "Automation"
    case privacy = "Privacy"

    var id: String { rawValue }
}

private enum MacSettingsTab: String, CaseIterable, Identifiable, Hashable {
    case general
    case hotkey
    case openAI
    case dictionary
    case permissions

    var id: String { rawValue }

    var group: MacSettingsSidebarGroup {
        switch self {
        case .general, .openAI, .dictionary:
            return .workspace
        case .hotkey:
            return .automation
        case .permissions:
            return .privacy
        }
    }

    var title: String {
        switch self {
        case .general:
            return "General"
        case .hotkey:
            return "Hotkey"
        case .openAI:
            return "AI"
        case .dictionary:
            return "Dictionary"
        case .permissions:
            return "Permissions"
        }
    }

    var subtitle: String {
        switch self {
        case .general:
            return "Behavior, audio routing, updates, and shell preferences."
        case .hotkey:
            return "Global keyboard shortcuts for starting dictation."
        case .openAI:
            return "Cloud provider, rewrite behavior, translation, and credentials."
        case .dictionary:
            return "Personal dictionary entries used during transcription and rewrite."
        case .permissions:
            return "Microphone and accessibility access required by the shell."
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

    var searchTokens: [String] {
        switch self {
        case .general:
            return ["configuration", "microphone", "updates", "dock", "launch at login", "sounds"]
        case .hotkey:
            return ["shortcut", "keyboard", "recorder", "dictation"]
        case .openAI:
            return ["provider", "api key", "translation", "rewrite", "groq", "openai"]
        case .dictionary:
            return ["entries", "personal dictionary", "names", "brands"]
        case .permissions:
            return ["microphone", "accessibility", "text injection", "privacy"]
        }
    }

    func matches(searchText: String) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }

        let terms = [title, subtitle] + searchTokens
        return terms.contains { $0.localizedCaseInsensitiveContains(query) }
    }
}

struct MacSettingsView: View {
    @EnvironmentObject private var appModel: MacAppModel

    @StateObject private var dictionaryViewModel = DictionaryViewModel()
    @StateObject private var openAISettingsViewModel = MacOpenAISettingsViewModel()
    @State private var selectedTab: MacSettingsTab? = .general
    @State private var searchText = ""
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
        } detail: {
            detail
        }
        .searchable(text: $searchText, prompt: "Search settings")
        .frame(minWidth: 920, minHeight: 700)
        .task {
            reloadStateFromPreferences()
            synchronizeSelectionWithFilter()
        }
        .onChange(of: searchText) { _, _ in
            synchronizeSelectionWithFilter()
        }
        .onAppear {
            appModel.settingsDidAppear()
        }
        .onDisappear {
            appModel.settingsDidDisappear()
        }
    }

    private var sidebar: some View {
        List(selection: $selectedTab) {
            if filteredTabs.isEmpty {
                ContentUnavailableView(
                    "No Results",
                    systemImage: "magnifyingglass",
                    description: Text("Try a different keyword.")
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .tag(Optional<MacSettingsTab>.none)
            } else {
                ForEach(MacSettingsSidebarGroup.allCases) { group in
                    let tabs = filteredTabs(in: group)

                    if !tabs.isEmpty {
                        Section(group.rawValue) {
                            ForEach(tabs) { tab in
                                NavigationLink(value: tab) {
                                    sidebarRow(for: tab)
                                }
                            }
                        }
                    }
                }
            }
        }
        .environment(\.sidebarRowSize, .large)
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 320)
    }

    @ViewBuilder
    private var detail: some View {
        if let activeTab {
            selectedContent(for: activeTab)
                .navigationTitle(activeTab.title)
                .navigationSubtitle(activeTab.subtitle)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            ContentUnavailableView(
                "Select a Section",
                systemImage: "sidebar.left",
                description: Text("Choose a destination from the sidebar.")
            )
        }
    }

    @ViewBuilder
    private func sidebarRow(for tab: MacSettingsTab) -> some View {
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

    @ViewBuilder
    private func selectedContent(for tab: MacSettingsTab) -> some View {
        switch tab {
        case .general:
            MacGeneralSettingsView()
        case .hotkey:
            MacHotkeySettingsView()
        case .openAI:
            MacOpenAISettingsView(viewModel: openAISettingsViewModel)
        case .dictionary:
            DictionaryView(viewModel: dictionaryViewModel)
        case .permissions:
            MacPermissionsSettingsView()
        }
    }

    private var activeTab: MacSettingsTab? {
        if let selectedTab, filteredTabs.contains(selectedTab) {
            return selectedTab
        }

        return filteredTabs.first
    }

    private var filteredTabs: [MacSettingsTab] {
        MacSettingsTab.allCases.filter { $0.matches(searchText: searchText) }
    }

    private func filteredTabs(in group: MacSettingsSidebarGroup) -> [MacSettingsTab] {
        filteredTabs.filter { $0.group == group }
    }

    private var hasPermissionIssues: Bool {
        appModel.microphoneAccessNeedsAttention ||
            appModel.autoPasteAccessNeedsAttention
    }

    private func reloadStateFromPreferences() {
        openAISettingsViewModel.load()
        dictionaryViewModel.load()
    }

    private func synchronizeSelectionWithFilter() {
        if let selectedTab, filteredTabs.contains(selectedTab) {
            return
        }

        selectedTab = filteredTabs.first
    }
}
#endif
