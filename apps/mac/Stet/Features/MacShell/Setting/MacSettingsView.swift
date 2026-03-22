#if os(macOS)
import SwiftUI
internal import Auth

private enum MacSettingsSidebarGroup: String, CaseIterable, Identifiable {
    case workspace = "Workspace"
    case automation = "Automation"

    var id: String { rawValue }
}

private enum MacSettingsTab: String, CaseIterable, Identifiable, Hashable {
    case general
    case hotkey
    case openAI
    case dictionary

    var id: String { rawValue }

    var group: MacSettingsSidebarGroup {
        switch self {
        case .general, .openAI, .dictionary:
            return .workspace
        case .hotkey:
            return .automation
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
        }
    }

    var subtitle: String {
        switch self {
        case .general:
            return "Behavior, audio routing, updates, and shell preferences."
        case .hotkey:
            return "Global keyboard shortcuts for starting dictation."
        case .openAI:
            return "Cloud provider, rewrite behavior, and credentials."
        case .dictionary:
            return "Personal dictionary entries used during transcription and rewrite."
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
        }
    }

    var searchTokens: [String] {
        switch self {
        case .general:
            return ["configuration", "microphone", "updates", "dock", "launch at login", "sounds", "theme", "appearance", "colors", "shader"]
        case .hotkey:
            return ["shortcut", "keyboard", "recorder", "dictation"]
        case .openAI:
            return ["provider", "api key", "rewrite", "groq", "openai"]
        case .dictionary:
            return ["entries", "personal dictionary", "names", "brands"]
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
    @EnvironmentObject private var settingsShellViewModel: MacSettingsShellViewModel

    @StateObject private var dictionaryViewModel = DictionaryViewModel()
    @StateObject private var openAISettingsViewModel = MacOpenAISettingsViewModel()
    private let supabase = SupabaseService.shared
    @State private var selectedTab: MacSettingsTab? = .general
    @State private var isShowingAccountSheet = false
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
        .sheet(isPresented: $isShowingAccountSheet) {
            AuthView()
                .frame(minWidth: 520, minHeight: 480)
        }
        .onChange(of: searchText) { _, _ in
            synchronizeSelectionWithFilter()
        }
        .onAppear {
            settingsShellViewModel.settingsDidAppear()
        }
        .onDisappear {
            settingsShellViewModel.settingsDidDisappear()
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            Button {
                isShowingAccountSheet = true
            } label: {
                sidebarAccountRow
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.plain)

            Divider()

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
        }
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
        Label(tab.title, systemImage: tab.iconName)
    }

    private var sidebarAccountRow: some View {
        HStack(spacing: 12) {
            accountAvatar

            VStack(alignment: .leading, spacing: 2) {
                Text(accountTitle)
                    .font(.headline)
                    .lineLimit(1)

                Text(accountSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var accountAvatar: some View {
        ZStack(alignment: .bottomTrailing) {
            Circle()
                .fill(
                    LinearGradient(
                        colors: accountAvatarGradient,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 42, height: 42)
                .overlay {
                    Text(accountInitials)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }

            Circle()
                .fill(supabase.currentSession == nil ? Color.secondary.opacity(0.6) : Color.green)
                .frame(width: 10, height: 10)
                .overlay {
                    Circle()
                        .stroke(Color(nsColor: .controlBackgroundColor), lineWidth: 2)
                }
        }
        .accessibilityHidden(true)
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

    private var accountTitle: String {
        if let email = supabase.currentSession?.user.email, !email.isEmpty {
            return email
        }

        return "Stet Account"
    }

    private var accountSubtitle: String {
        if supabase.currentSession == nil {
            return supabase.isConfigured ? "Sign in for relay-backed features" : "Supabase setup required"
        }

        return "Signed in"
    }

    private var accountInitials: String {
        let source = supabase.currentSession?.user.email ?? "Stet"
        let components = source
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { !$0.isEmpty }

        let letters = components
            .prefix(2)
            .compactMap { $0.first.map { String($0).uppercased() } }
            .joined()

        return letters.isEmpty ? "S" : letters
    }

    private var accountAvatarGradient: [Color] {
        if supabase.currentSession == nil {
            return [Color.secondary.opacity(0.75), Color.secondary.opacity(0.45)]
        }

        return [Color.accentColor.opacity(0.95), Color.accentColor.opacity(0.65)]
    }
}
#endif
