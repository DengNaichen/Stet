#if os(macOS)
    import SwiftUI

    private enum MacSettingsSection: String, CaseIterable, Identifiable {
        case app
        case dictation
        case listening
        case text
        case library

        var id: String { rawValue }

        var title: String {
            switch self {
            case .app:
                return "App"
            case .dictation:
                return "Dictation"
            case .listening:
                return "Listening"
            case .text:
                return "Text"
            case .library:
                return "Library"
            }
        }
    }

    private enum MacSettingsTab: String, CaseIterable, Identifiable, Hashable {
        case general
        case appearance
        case dictation
        case microphone
        case transcription
        case voice
        case meetings
        case openAI
        case dictionary
        case history
        #if DEBUG
            case shaderDebug
        #endif

        var id: String { rawValue }

        var isAvailable: Bool {
            switch self {
            case .voice:
                return MacFeatureAvailability.isPassiveListeningVisible
            default:
                return true
            }
        }

        var section: MacSettingsSection {
            switch self {
            case .general, .appearance:
                return .app
            case .dictation, .microphone, .transcription:
                return .dictation
            case .voice, .meetings:
                return .listening
            case .openAI, .dictionary:
                return .text
            case .history:
                return .library
            #if DEBUG
                case .shaderDebug:
                    return .library
            #endif
            }
        }

        var title: String {
            switch self {
            case .general:
                return "General"
            case .appearance:
                return "Theme"
            case .dictation:
                return "Dictation"
            case .microphone:
                return "Microphone"
            case .transcription:
                return "Transcription"
            case .voice:
                return "Voice"
            case .meetings:
                return "Meetings"
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
                return "Launch at login, Dock, and updates."
            case .appearance:
                return "Dictation capsule theme and color palette."
            case .dictation:
                return "Global shortcut and dictation feedback."
            case .microphone:
                return "Microphone selection and recording test."
            case .transcription:
                return "On-device transcription engine and models."
            case .voice:
                return "Passive listening and speaker profiles."
            case .meetings:
                return "Record in-room conversations and open saved meeting folders."
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
            case .appearance:
                return "circle.lefthalf.filled"
            case .dictation:
                return "command"
            case .microphone:
                return "mic.fill"
            case .transcription:
                return "waveform"
            case .voice:
                return "person.wave.2.fill"
            case .meetings:
                return "person.3.fill"
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
            case .appearance:
                return Color(nsColor: .systemBlue)
            case .dictation:
                return Color(nsColor: .systemGray)
            case .microphone:
                return Color(nsColor: .systemRed)
            case .transcription:
                return Color(nsColor: .systemPurple)
            case .voice:
                return Color(nsColor: .systemTeal)
            case .meetings:
                return Color(nsColor: .systemOrange)
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
                return ["updates", "dock", "launch at login", "behavior"]
            case .appearance:
                return ["theme", "colors", "shader", "capsule", "visual"]
            case .dictation:
                return [
                    "shortcut", "keyboard", "recorder", "dictation", "sounds", "notification", "capture",
                    "mute", "feedback",
                ]
            case .microphone:
                return ["microphone", "input device", "recording", "audio", "test"]
            case .transcription:
                return ["whisper", "parakeet", "nano", "engine", "model", "transcription", "download"]
            case .voice:
                return [
                    "passive transcription", "speaker profile", "speaker name", "enrollment", "listening",
                ]
            case .meetings:
                return ["meeting", "record", "transcript", "folder", "shortcut", "speaker"]
            case .openAI:
                return [
                    "service", "access key", "sign in", "transcript", "improve", "rewrite", "openai",
                    "apple intelligence", "foundation models", "local refine", "custom", "base url",
                    "openai compatible",
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
                        ForEach(MacSettingsSection.allCases) { section in
                            let tabs = filteredTabs.filter { $0.section == section }
                            if !tabs.isEmpty {
                                Section(section.title) {
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
            case .appearance:
                MacAppearanceSettingsView()
            case .dictation:
                MacDictationSettingsView()
            case .microphone:
                MacMicrophoneSettingsView()
            case .transcription:
                MacTranscriptionSettingsView()
            case .voice:
                MacVoiceSettingsView()
            case .meetings:
                MacMeetingSettingsView()
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
            MacSettingsTab.allCases.filter { $0.isAvailable && $0.matches(searchText: searchText) }
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
