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
        #if DEBUG
            case shaderDebug
        #endif

        var id: String { rawValue }

        var title: String {
            switch self {
            case .general:
                return "General"
            case .audio:
                return "Audio"
            case .appearance:
                return "Theme"
            case .hotkey:
                return "Hotkey"
            case .openAI:
                return "Refine"
            case .dictionary:
                return "Dictionary"
            #if DEBUG
                case .shaderDebug:
                    return "Debug"
            #endif
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
            #if DEBUG
                case .shaderDebug:
                    return "Large shader preview and color input controls."
            #endif
            }
        }

        var iconName: String {
            switch self {
            case .general:
                return "gearshape.fill"
            case .audio:
                return "speaker.wave.3.fill"
            case .appearance:
                return "circle.lefthalf.filled"
            case .hotkey:
                return "command"
            case .openAI:
                return "pencil"
            case .dictionary:
                return "text.book.closed.fill"
            #if DEBUG
                case .shaderDebug:
                    return "hammer.fill"
            #endif
            }
        }

        var iconColor: Color {
            switch self {
            case .general:
                return Color(nsColor: .systemGray)
            case .audio:
                return Color(nsColor: .systemRed)
            case .appearance:
                return Color(nsColor: .systemBlue)
            case .hotkey:
                return Color(nsColor: .systemGray)
            case .openAI:
                return Color(nsColor: .systemGreen)
            case .dictionary:
                return Color(nsColor: .systemGray)
            #if DEBUG
                case .shaderDebug:
                    return Color(nsColor: .systemBrown)
            #endif
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
            #if DEBUG
                case .shaderDebug:
                    return ["shader", "preview", "debug", "window", "colors"]
            #endif
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

                Button {
                    isShowingAccountSheet = true
                } label: {
                    sidebarAccountRow
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, MacUI.SettingsViewMetrics.sidebarAccountRowHorizontalPadding)
                        .padding(.vertical, MacUI.SettingsViewMetrics.sidebarAccountRowVerticalPadding)
                }
                .buttonStyle(.plain)
            }
            .navigationSplitViewColumnWidth(min: 144, ideal: 176, max: 240)
        }

        @ViewBuilder
        private var detail: some View {
            if let activeTab {
                selectedContent(for: activeTab)
                    .navigationTitle(activeTab.title)
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
            HStack(spacing: 8) {
                ZStack {
                    // 1. Shadow anchoring
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.black.opacity(0.1))
                        .offset(y: 0.5)
                        .blur(radius: 0.5)

                    // 2. Main color tile
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(tab.iconColor.gradient)

                    // 3. Highlight border
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)

                    // 4. Smaller symbol for a more delicate look
                    Image(systemName: tab.iconName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white)
                        .shadow(color: Color.black.opacity(0.05), radius: 0, x: 0, y: 0.5)
                }
                .frame(width: 20, height: 20)

                Text(tab.title)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
            }
            .padding(.vertical, 3)
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

        private var accountAvatarURL: URL? {
            guard let urlString = supabase.currentSession?.user.userMetadata["avatar_url"]?.stringValue else {
                return nil
            }
            return URL(string: urlString)
        }

        private var accountAvatar: some View {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let url = accountAvatarURL {
                        AsyncImage(url: url) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            initialsAvatar
                        }
                        .frame(width: 30, height: 30)
                        .clipShape(Circle())
                    } else {
                        initialsAvatar
                    }
                }

                Circle()
                    .fill(supabase.currentSession == nil ? Color.secondary.opacity(0.6) : Color.green)
                    .frame(width: 8, height: 8)
                    .overlay {
                        Circle()
                            .stroke(Color(nsColor: .controlBackgroundColor), lineWidth: 1.5)
                    }
            }
            .accessibilityHidden(true)
        }

        private var initialsAvatar: some View {
            Circle()
                .fill(
                    LinearGradient(
                        colors: accountAvatarGradient,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 30, height: 30)
                .overlay {
                    Text(accountInitials)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }
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
                MacOpenAISettingsView(viewModel: openAISettingsViewModel) {
                    isShowingAccountSheet = true
                }
            case .dictionary:
                DictionaryView(viewModel: dictionaryViewModel)
            #if DEBUG
                case .shaderDebug:
                    MacShaderDebugSettingsView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            #endif
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
