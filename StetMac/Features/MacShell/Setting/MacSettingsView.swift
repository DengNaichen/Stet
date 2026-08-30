#if os(macOS)
    import SwiftUI

    private enum MacSettingsTab: String, CaseIterable, Identifiable, Hashable {
        case general
        case audio
        case appearance
        case hotkey
        case openAI
        case dictionary
        case history
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
            case .history:
                return "History"
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
            case .history:
                return "Searchable log of every dictation session."
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
            case .history:
                return "clock.arrow.circlepath"
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
            case .history:
                return Color(nsColor: .systemIndigo)
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
                return [
                    "microphone", "input device", "recording", "audio", "test", "passive transcription",
                    "speaker profile", "speaker name",
                ]
            case .appearance:
                return ["theme", "colors", "shader", "capsule", "visual"]
            case .hotkey:
                return ["shortcut", "keyboard", "recorder", "dictation"]
            case .openAI:
                return [
                    "service", "access key", "sign in", "transcript", "improve", "rewrite", "groq", "openai",
                    "apple intelligence", "foundation models", "local refine",
                ]
            case .dictionary:
                return ["entries", "personal dictionary", "names", "brands"]
            case .history:
                return ["log", "history", "sessions", "transcription", "export", "json", "past"]
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
            .frame(minWidth: 644, minHeight: 490)
            .task {
                reloadStateFromPreferences()
                synchronizeSelectionWithFilter()
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

            }
            .navigationSplitViewColumnWidth(min: 144, ideal: 176, max: 240)
        }

        @ViewBuilder
        private var detail: some View {
            if let activeTab {
                selectedContent(for: activeTab)
                    .navigationTitle(LocalizedStringKey(activeTab.title))
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

                Text(LocalizedStringKey(tab.title))
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
            }
            .padding(.vertical, 3)
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
            case .history:
                MacHistorySettingsView()
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

    }
#endif
