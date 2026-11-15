#if os(macOS)
    import Combine
    import SwiftUI

    enum MacSettingsSection: String, CaseIterable, Identifiable {
        case app, dictation, intelligence, advanced

        var id: String { rawValue }

        var title: String {
            switch self {
            case .app: return "App"
            case .dictation: return "Dictation"
            case .intelligence: return "Intelligence"
            case .advanced: return "Advanced"
            }
        }
    }

    enum MacSettingsTab: String, CaseIterable, Identifiable, Hashable {
        case general, dictation, microphone, transcription, openAI, mcp
        #if DEBUG
            case shaderDebug
        #endif

        var id: String { rawValue }

        var isAvailable: Bool { true }

        var section: MacSettingsSection {
            switch self {
            case .general: return .app
            case .dictation, .microphone, .transcription: return .dictation
            case .openAI: return .intelligence
            case .mcp: return .advanced
            #if DEBUG
                case .shaderDebug: return .advanced
            #endif
            }
        }

        var title: String {
            switch self {
            case .general: return "General"
            case .dictation: return "Shortcut"
            case .microphone: return "Microphone"
            case .transcription: return "Transcription"
            case .openAI: return "Refine"
            case .mcp: return "MCP"
            #if DEBUG
                case .shaderDebug: return "Debug"
            #endif
            }
        }

        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .dictation: return "command"
            case .microphone: return "mic"
            case .transcription: return "waveform"
            case .openAI: return "sparkles"
            case .mcp: return "point.3.connected.trianglepath.dotted"
            #if DEBUG
                case .shaderDebug: return "ladybug"
            #endif
            }
        }

        var searchKeywords: String {
            switch self {
            case .general: return "general launch login dock updates compatibility onboarding"
            case .dictation: return "shortcut hotkey sound notification mute feedback dictation"
            case .microphone: return "microphone audio input device hardware level test"
            case .transcription: return "transcription model engine funasr parakeet apple speech ane coreml"
            case .openAI: return "refine ai rewrite model api key provider openai anthropic groq endpoint custom"
            case .mcp: return "mcp server coding agent claude codex cursor http calendar tools"
            #if DEBUG
                case .shaderDebug: return "debug shader workbench"
            #endif
            }
        }

        func matches(_ query: String) -> Bool {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return true }
            let normalized = trimmed.lowercased()
            return title.lowercased().contains(normalized) || searchKeywords.contains(normalized)
        }
    }

    @MainActor
    final class MacSettingsNavigationState: ObservableObject {
        @Published var selectedTab: MacSettingsTab = .general
        @Published var searchQuery = ""
        let dictionaryViewModel = DictionaryViewModel()
        let openAISettingsViewModel = MacOpenAISettingsViewModel()
        let titleScrollStore = MacSettingsTitleScrollStore()

        var visibleTabs: [MacSettingsTab] {
            MacSettingsTab.allCases.filter(\.isAvailable)
        }

        var filteredTabs: [MacSettingsTab] {
            visibleTabs.filter { $0.matches(searchQuery) }
        }

        var activeTab: MacSettingsTab {
            if filteredTabs.contains(selectedTab) {
                return selectedTab
            }
            return filteredTabs.first ?? (visibleTabs.first ?? .general)
        }

        func reloadStateFromPreferences() {
            openAISettingsViewModel.load()
            dictionaryViewModel.load()
        }

        func synchronizeSelection() {
            if visibleTabs.contains(selectedTab) {
                return
            }
            selectedTab = visibleTabs.first ?? .general
        }
    }

    struct MacSettingsSidebarView: View {
        @ObservedObject var state: MacSettingsNavigationState
        var onBack: (() -> Void)? = nil
        @State private var isHoveringBack = false

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
                        .onHover { isHoveringBack = $0 }
                        .accessibilityLabel("Back to Stet")
                        .help("Back to Stet")
                    }

                    LinearSearchField(
                        placeholder: "Filter settings…",
                        text: $state.searchQuery,
                        height: 27,
                        fillColor: MacUI.LinearSurfaces.glassInset,
                        isBorderless: true
                    )
                }
                .padding(.horizontal, MacUI.LinearMetrics.sidebarHorizontalPadding)
                .padding(.top, 2)
                .padding(.bottom, 10)

                ScrollView {
                    VStack(alignment: .leading, spacing: MacUI.LinearMetrics.sidebarSectionGap) {
                        if state.filteredTabs.isEmpty {
                            Text("No matching settings")
                                .font(MacUI.LinearTypography.rowSubtitle)
                                .foregroundStyle(MacUI.LinearSurfaces.mutedInk)
                                .padding(.horizontal, 9)
                                .padding(.top, 4)
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
                                                LinearSidebarNavRow(
                                                    title: LocalizedStringKey(tab.title),
                                                    systemImage: tab.icon,
                                                    isSelected: tab == state.activeTab
                                                ) {
                                                    state.selectedTab = tab
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
                .onChange(of: state.selectedTab) { _, _ in
                    state.titleScrollStore.reset()
                }
                .environment(\.macSettingsTitleScrollStore, state.titleScrollStore)
        }

        @ViewBuilder
        private func selectedContent(for tab: MacSettingsTab) -> some View {
            switch tab {
            case .general:
                MacGeneralSettingsView()
            case .dictation:
                MacDictationSettingsView()
            case .microphone:
                MacMicrophoneSettingsView()
            case .transcription:
                MacTranscriptionSettingsView()
            case .openAI:
                MacOpenAISettingsView(viewModel: state.openAISettingsViewModel)
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
