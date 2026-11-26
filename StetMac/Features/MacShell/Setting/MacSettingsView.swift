#if os(macOS)
    import Combine
    import SwiftUI

    enum MacSettingsSection: String, CaseIterable, Identifiable {
        case app, dictation, advanced

        var id: String { rawValue }

        var title: String {
            switch self {
            case .app: return "App"
            case .dictation: return "Dictation"
            case .advanced: return "Advanced"
            }
        }
    }

    enum MacSettingsTargetSection: String, Hashable {
        case application
        case updates
        case dictationIndicator
        case shortcuts
        case feedback
        case pastingCompatibility
        case audioInputDevice
        case inputTest
        case onDeviceTranscription
        case aiRefine
        case mcpServer
        case calendarTools
    }

    struct MacSettingsSearchItem: Hashable {
        let sectionHint: String
        let targetSection: MacSettingsTargetSection?
        let keywords: [String]
    }

    enum MacSettingsTab: String, CaseIterable, Identifiable, Hashable {
        case general, appearance, dictation, microphone, speechAndRefine, mcp
        #if DEBUG
            case shaderDebug
        #endif

        var id: String { rawValue }

        var isAvailable: Bool { true }

        var section: MacSettingsSection {
            switch self {
            case .general, .appearance: return .app
            case .dictation, .microphone, .speechAndRefine: return .dictation
            case .mcp: return .advanced
            #if DEBUG
                case .shaderDebug: return .advanced
            #endif
            }
        }

        var title: String {
            switch self {
            case .general: return "General"
            case .appearance: return "Appearance"
            case .dictation: return "Dictation"
            case .microphone: return "Microphone"
            case .speechAndRefine: return "Speech & Refine"
            case .mcp: return "MCP"
            #if DEBUG
                case .shaderDebug: return "Debug"
            #endif
            }
        }

        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .appearance: return "paintbrush"
            case .dictation: return "command"
            case .microphone: return "mic"
            case .speechAndRefine: return "waveform"
            case .mcp: return "point.3.connected.trianglepath.dotted"
            #if DEBUG
                case .shaderDebug: return "ladybug"
            #endif
            }
        }

        var searchItems: [MacSettingsSearchItem] {
            switch self {
            case .general:
                var items = [
                    MacSettingsSearchItem(
                        sectionHint: "Application",
                        targetSection: .application,
                        keywords: [
                            "general", "app", "application", "launch", "login", "startup", "dock", "menu bar",
                            "menubar",
                        ]
                    ),
                    MacSettingsSearchItem(
                        sectionHint: "Updates",
                        targetSection: .updates,
                        keywords: ["update", "updates", "automatic", "check for updates", "version"]
                    ),
                ]
                #if DEBUG
                    items.append(
                        MacSettingsSearchItem(
                            sectionHint: "Debug",
                            targetSection: nil,
                            keywords: ["debug", "onboarding", "restart"]
                        )
                    )
                #endif
                return items
            case .appearance:
                return [
                    MacSettingsSearchItem(
                        sectionHint: "Dictation Indicator",
                        targetSection: .dictationIndicator,
                        keywords: [
                            "appearance", "theme", "themes", "capsule", "indicator", "color", "visual", "style",
                            "preview", "cover flow", "orb", "shader",
                        ]
                    )
                ]
            case .dictation:
                return [
                    MacSettingsSearchItem(
                        sectionHint: "Shortcuts",
                        targetSection: .shortcuts,
                        keywords: [
                            "dictation", "shortcut", "shortcuts", "hotkey", "hotkeys", "key", "keyboard",
                            "start dictation", "meeting", "record meeting", "meeting shortcut", "meeting recording",
                            "trigger",
                        ]
                    ),
                    MacSettingsSearchItem(
                        sectionHint: "Feedback",
                        targetSection: .feedback,
                        keywords: [
                            "feedback", "sound", "sounds", "interaction sounds", "notification", "notifications",
                            "notify", "mute", "background audio", "pause media",
                        ]
                    ),
                    MacSettingsSearchItem(
                        sectionHint: "Pasting & App Compatibility",
                        targetSection: .pastingCompatibility,
                        keywords: [
                            "compatibility", "app compatibility", "compatibility list", "paste", "pasting",
                            "auto-paste", "autopaste", "insert", "insertion", "clipboard", "blocked", "target app",
                        ]
                    ),
                ]
            case .microphone:
                return [
                    MacSettingsSearchItem(
                        sectionHint: "Audio Input Device",
                        targetSection: .audioInputDevice,
                        keywords: [
                            "microphone", "mic", "audio", "input", "device", "hardware", "select microphone",
                            "permission",
                        ]
                    ),
                    MacSettingsSearchItem(
                        sectionHint: "Input Test",
                        targetSection: .inputTest,
                        keywords: ["level", "test", "recording", "playback", "volume", "no speech", "input test"]
                    ),
                ]
            case .speechAndRefine:
                return [
                    MacSettingsSearchItem(
                        sectionHint: "On-Device Transcription",
                        targetSection: .onDeviceTranscription,
                        keywords: [
                            "speech", "transcription", "transcribe", "local", "on-device", "ondevice", "offline",
                            "engine", "local engine", "model", "models", "downloaded models", "fun-asr", "funasr",
                            "nano", "parakeet", "fluidaudio", "apple speech", "cpu", "ane", "coreml", "acceleration",
                            "download",
                        ]
                    ),
                    MacSettingsSearchItem(
                        sectionHint: "AI Refine",
                        targetSection: .aiRefine,
                        keywords: [
                            "refine", "ai", "ai refine", "llm", "rewrite", "cleanup", "improve",
                            "transcript improvement", "privacy", "cloud", "api", "api key", "key", "credentials",
                            "provider", "openai", "google", "gemini", "deepseek", "qwen", "glm",
                            "apple intelligence", "custom", "endpoint", "server", "thinking", "thinking level",
                            "catalog",
                        ]
                    ),
                ]
            case .mcp:
                return [
                    MacSettingsSearchItem(
                        sectionHint: "MCP Server",
                        targetSection: .mcpServer,
                        keywords: [
                            "mcp", "server", "coding agent", "agent", "claude", "codex", "cursor", "http",
                            "setup prompt", "local",
                        ]
                    ),
                    MacSettingsSearchItem(
                        sectionHint: "Calendar Tools",
                        targetSection: .calendarTools,
                        keywords: ["calendar", "tools", "meetings"]
                    ),
                ]
            #if DEBUG
                case .shaderDebug:
                    return [
                        MacSettingsSearchItem(
                            sectionHint: "Shader Debug Window",
                            targetSection: nil,
                            keywords: ["debug", "shader", "workbench"]
                        )
                    ]
            #endif
            }
        }

        func matches(_ query: String) -> Bool {
            let tokens = Self.queryTokens(from: query)
            guard !tokens.isEmpty else { return true }
            let corpus = [title.lowercased()] + searchItems.flatMap { [$0.sectionHint.lowercased()] + $0.keywords }
            return tokens.allSatisfy { token in
                corpus.contains { $0.contains(token) }
            }
        }

        func matchedSearchItem(for query: String) -> MacSettingsSearchItem? {
            let tokens = Self.queryTokens(from: query)
            guard !tokens.isEmpty, matches(query) else { return nil }

            let normalizedQuery = tokens.joined(separator: " ")
            if title.lowercased().hasPrefix(normalizedQuery) {
                return nil
            }

            let scored = searchItems.map { item -> (item: MacSettingsSearchItem, matchCount: Int) in
                let fields = [item.sectionHint.lowercased()] + item.keywords
                let matchCount = tokens.filter { token in
                    fields.contains { $0.contains(token) }
                }.count
                return (item, matchCount)
            }

            if let exactMatch = scored.first(where: { $0.matchCount == tokens.count }) {
                return exactMatch.item
            }

            let titleLower = title.lowercased()
            let nonTitleTokens = tokens.filter { !titleLower.contains($0) }
            if !nonTitleTokens.isEmpty,
                let bestNonTitle = searchItems.max(by: { lhs, rhs in
                    let lhsFields = [lhs.sectionHint.lowercased()] + lhs.keywords
                    let rhsFields = [rhs.sectionHint.lowercased()] + rhs.keywords
                    let lhsCount = nonTitleTokens.filter { t in lhsFields.contains { $0.contains(t) } }.count
                    let rhsCount = nonTitleTokens.filter { t in rhsFields.contains { $0.contains(t) } }.count
                    return lhsCount < rhsCount
                })
            {
                let bestFields = [bestNonTitle.sectionHint.lowercased()] + bestNonTitle.keywords
                if nonTitleTokens.contains(where: { t in bestFields.contains { $0.contains(t) } }) {
                    return bestNonTitle
                }
            }

            return scored.first(where: { $0.matchCount > 0 })?.item
        }

        func matchedSectionHint(for query: String) -> String? {
            matchedSearchItem(for: query)?.sectionHint
        }

        private static func queryTokens(from query: String) -> [String] {
            query
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .split(whereSeparator: \.isWhitespace)
                .map(String.init)
        }
    }

    @MainActor
    final class MacSettingsNavigationState: ObservableObject {
        @Published var selectedTab: MacSettingsTab = .general {
            didSet {
                updateLastVisibleTab()
            }
        }
        @Published var searchQuery = "" {
            didSet {
                if !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    targetSection = nil
                }
                updateLastVisibleTab()
            }
        }
        @Published var targetSection: MacSettingsTargetSection?
        @Published private(set) var navigationRevision = 0
        private var lastVisibleTab: MacSettingsTab = .general

        let openAISettingsViewModel = MacOpenAISettingsViewModel()
        let titleScrollStore = MacSettingsTitleScrollStore()

        var visibleTabs: [MacSettingsTab] {
            MacSettingsTab.allCases.filter(\.isAvailable)
        }

        var filteredTabs: [MacSettingsTab] {
            visibleTabs.filter { $0.matches(searchQuery) }
        }

        var activeTab: MacSettingsTab {
            if filteredTabs.isEmpty {
                return lastVisibleTab
            }
            if filteredTabs.contains(selectedTab) {
                return selectedTab
            }
            return filteredTabs.first ?? lastVisibleTab
        }

        var effectiveTargetSection: MacSettingsTargetSection? {
            if let targetSection {
                return targetSection
            }
            return activeTab.matchedSearchItem(for: searchQuery)?.targetSection
        }

        func selectTab(_ tab: MacSettingsTab) {
            selectedTab = tab
            targetSection = tab.matchedSearchItem(for: searchQuery)?.targetSection
            navigationRevision += 1
        }

        func navigate(to tab: MacSettingsTab, section: MacSettingsTargetSection? = nil) {
            searchQuery = ""
            selectedTab = tab
            targetSection = section
            navigationRevision += 1
        }

        func clearFilter() {
            searchQuery = ""
            targetSection = nil
        }

        func reloadStateFromPreferences() {
            openAISettingsViewModel.load()
        }

        func synchronizeSelection() {
            if visibleTabs.contains(selectedTab) {
                updateLastVisibleTab()
                return
            }
            selectedTab = visibleTabs.first ?? .general
        }

        private func updateLastVisibleTab() {
            let matches = filteredTabs
            if matches.contains(selectedTab) {
                lastVisibleTab = selectedTab
            } else if let first = matches.first {
                lastVisibleTab = first
            }
        }
    }

    struct MacSettingsSidebarView: View {
        @ObservedObject var state: MacSettingsNavigationState
        var onBack: (() -> Void)? = nil
        @State private var isHoveringBack = false
        @FocusState private var isSearchFocused: Bool

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    if let onBack {
                        Button {
                            onBack()
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 10.5, weight: .semibold))
                                Text("Back to app")
                                    .font(.system(size: 12.5, weight: .regular))
                            }
                            .foregroundStyle(
                                isHoveringBack ? MacUI.Foreground.primary : MacUI.Foreground.secondaryColor
                            )
                            .padding(.horizontal, 9)
                            .frame(height: 24)
                            .background {
                                if isHoveringBack {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(MacUI.LinearSurfaces.sidebarHover)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut("[", modifiers: .command)
                        .onHover { isHoveringBack = $0 }
                        .accessibilityLabel("Back to Stet")
                        .help("Back to Stet (⌘[)")
                    }

                    LinearSearchField(
                        placeholder: "Filter settings…",
                        text: $state.searchQuery,
                        height: 27,
                        fillColor: MacUI.LinearSurfaces.glassInset,
                        isBorderless: true,
                        focusBinding: $isSearchFocused,
                        onEscape: {
                            state.clearFilter()
                        }
                    )
                }
                .padding(.horizontal, MacUI.LinearMetrics.sidebarHorizontalPadding)
                .padding(.top, 2)
                .padding(.bottom, 10)

                ScrollView {
                    VStack(alignment: .leading, spacing: MacUI.LinearMetrics.sidebarSectionGap) {
                        if state.filteredTabs.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("No matching settings")
                                    .font(MacUI.LinearTypography.sidebarSelected)
                                    .foregroundStyle(MacUI.Foreground.primary)

                                Text("Try keywords like \"paste\", \"shortcut\", or \"microphone\".")
                                    .font(MacUI.LinearTypography.rowSubtitle)
                                    .foregroundStyle(MacUI.LinearSurfaces.mutedInk)
                                    .fixedSize(horizontal: false, vertical: true)

                                Button("Clear Filter") {
                                    state.clearFilter()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            .padding(.horizontal, 9)
                            .padding(.top, 6)
                        } else {
                            ForEach(MacSettingsSection.allCases) { section in
                                let tabs = state.filteredTabs.filter { $0.section == section }
                                if !tabs.isEmpty {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(LocalizedStringKey(section.title))
                                            .font(MacUI.LinearTypography.sidebarGroup)
                                            .foregroundStyle(MacUI.LinearSurfaces.mutedInk)
                                            .padding(.horizontal, 9)
                                            .padding(.bottom, 1)

                                        VStack(spacing: MacUI.LinearMetrics.sidebarRowGap) {
                                            ForEach(tabs) { tab in
                                                let hint = tab.matchedSectionHint(for: state.searchQuery)
                                                LinearSidebarNavRow(
                                                    title: LocalizedStringKey(tab.title),
                                                    systemImage: tab.icon,
                                                    isSelected: tab == state.activeTab,
                                                    subtitle: hint.map { LocalizedStringKey($0) }
                                                ) {
                                                    state.selectTab(tab)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, MacUI.LinearMetrics.sidebarHorizontalPadding)
                    .padding(.bottom, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.hidden)
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .background {
                Button("") {
                    isSearchFocused = true
                }
                .keyboardShortcut("f", modifiers: .command)
                .labelsHidden()
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)
            }
        }
    }

    struct MacSettingsDetailView: View {
        @ObservedObject var state: MacSettingsNavigationState

        var body: some View {
            selectedContent(for: state.activeTab)
                .id(state.activeTab.id)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .task {
                    state.reloadStateFromPreferences()
                    state.synchronizeSelection()
                }
                .onChange(of: state.activeTab) { _, _ in
                    state.titleScrollStore.reset()
                }
                .environment(\.macSettingsTitleScrollStore, state.titleScrollStore)
        }

        @ViewBuilder
        private func selectedContent(for tab: MacSettingsTab) -> some View {
            switch tab {
            case .general:
                MacGeneralSettingsView(
                    scrollTarget: state.effectiveTargetSection,
                    scrollTrigger: state.navigationRevision
                )
            case .appearance:
                MacAppearanceSettingsView()
            case .dictation:
                MacDictationSettingsView(
                    scrollTarget: state.effectiveTargetSection,
                    scrollTrigger: state.navigationRevision
                )
            case .microphone:
                MacMicrophoneSettingsView()
            case .speechAndRefine:
                MacSpeechAndRefineSettingsView(
                    openAIViewModel: state.openAISettingsViewModel,
                    scrollTarget: state.effectiveTargetSection,
                    scrollTrigger: state.navigationRevision
                )
            case .mcp:
                MacMCPSettingsView()
            #if DEBUG
                case .shaderDebug:
                    MacShaderDebugSettingsView()
            #endif
            }
        }
    }

    struct MacSettingsView: View {
        @EnvironmentObject private var settingsShellViewModel: MacSettingsShellViewModel
        var onBack: (() -> Void)? = nil

        @StateObject private var state = MacSettingsNavigationState()
        @State private var columnVisibility: NavigationSplitViewVisibility = .all

        var body: some View {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                MacSettingsSidebarView(state: state, onBack: onBack)
                    .navigationSplitViewColumnWidth(
                        min: 196,
                        ideal: MacUI.LinearMetrics.sidebarWidth,
                        max: 250
                    )
                    .toolbar(removing: .sidebarToggle)
            } detail: {
                MacSettingsDetailView(state: state)
                    .background(MacUI.LinearSurfaces.detailCanvas.ignoresSafeArea())
            }
            .frame(
                minWidth: MacUI.LinearMetrics.windowMinWidth,
                minHeight: MacUI.LinearMetrics.windowMinHeight
            )
        }
    }
#endif
