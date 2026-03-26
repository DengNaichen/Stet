#if os(macOS)
    import SwiftUI
    internal import Auth

    private enum MacSettingsTab: String, CaseIterable, Identifiable, Hashable {
        case general
        case audio
        case appearance
        case hotkey
        case openAI
        case dictionary
        case shaderDebug

        var id: String { rawValue }

        var title: String {
            switch self {
            case .general:
                return "General"
            case .audio:
                return "Audio"
            case .appearance:
                return "Appearance"
            case .hotkey:
                return "Hotkey"
            case .openAI:
                return "AI"
            case .dictionary:
                return "Dictionary"
            case .shaderDebug:
                return "Debug"
            }
        }

        var subtitle: String {
            switch self {
            case .general:
                return "Behavior, updates, and shell preferences."
            case .audio:
                return "Microphone selection and recording test."
            case .appearance:
                return "Dictation capsule theme and color palette."
            case .hotkey:
                return "Global keyboard shortcuts for starting dictation."
            case .openAI:
                return "AI service, transcript improvement, and account access."
            case .dictionary:
                return "Personal dictionary entries used during transcription and transcript cleanup."
            case .shaderDebug:
                return "Large shader preview and color input controls."
            }
        }

        var iconName: String {
            switch self {
            case .general:
                return "slider.horizontal.3"
            case .audio:
                return "mic"
            case .appearance:
                return "paintbrush"
            case .hotkey:
                return "keyboard"
            case .openAI:
                return "key.horizontal"
            case .dictionary:
                return "text.book.closed"
            case .shaderDebug:
                return "hammer"
            }
        }

        var searchTokens: [String] {
            switch self {
            case .general:
                return ["updates", "dock", "launch at login", "sounds", "capture", "behavior"]
            case .audio:
                return ["microphone", "input device", "recording", "audio", "test"]
            case .appearance:
                return ["theme", "colors", "shader", "capsule", "visual"]
            case .hotkey:
                return ["shortcut", "keyboard", "recorder", "dictation"]
            case .openAI:
                return ["service", "access key", "sign in", "transcript", "improve", "rewrite", "groq", "openai"]
            case .dictionary:
                return ["entries", "personal dictionary", "names", "brands"]
            case .shaderDebug:
                return ["shader", "preview", "debug", "window", "colors"]
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
            .frame(minWidth: 644, minHeight: 490)
            .task {
                reloadStateFromPreferences()
                synchronizeSelectionWithFilter()
            }
            .sheet(
                isPresented: Binding(
                    get: { ReleaseHotfixFlags.loginEnabled && isShowingAccountSheet },
                    set: { isShowingAccountSheet = ReleaseHotfixFlags.loginEnabled && $0 }
                )
            ) {
                AuthView()
                    .frame(minWidth: 520, minHeight: 580)
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
                if ReleaseHotfixFlags.loginEnabled {
                    Button {
                        isShowingAccountSheet = true
                    } label: {
                        sidebarAccountRow
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, MacUI.SettingsViewMetrics.sidebarAccountRowHorizontalPadding)
                            .padding(.vertical, MacUI.SettingsViewMetrics.sidebarAccountRowVerticalPadding)
                    }
                    .buttonStyle(.plain)

                    Divider()
                }

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
                        ForEach(filteredTabs) { tab in
                            NavigationLink(value: tab) {
                                sidebarRow(for: tab)
                            }
                        }
                    }
                }
                .environment(\.sidebarRowSize, .large)
                .listStyle(.sidebar)
            }
            .navigationSplitViewColumnWidth(min: 144, ideal: 176, max: 240)
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

                VStack(alignment: .leading, spacing: 4) {
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
            case .audio:
                MacAudioSettingsView()
            case .appearance:
                MacAppearanceSettingsView()
            case .hotkey:
                MacHotkeySettingsView()
            case .openAI:
                MacOpenAISettingsView(viewModel: openAISettingsViewModel)
            case .dictionary:
                DictionaryView(viewModel: dictionaryViewModel)
            case .shaderDebug:
                MacShaderDebugSettingsView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
            let components =
                source
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .map(String.init)
                .filter { !$0.isEmpty }

            let letters =
                components
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
