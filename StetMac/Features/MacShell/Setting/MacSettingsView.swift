#if os(macOS)
    import SwiftUI

    private enum MacSettingsSection: String, CaseIterable, Identifiable {
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

    private enum MacSettingsTab: String, CaseIterable, Identifiable, Hashable {
        case general, dictation, microphone, transcription, openAI, mcp
        #if DEBUG
            case shaderDebug
        #endif

        var id: String { rawValue }

        var isAvailable: Bool {
            switch self {
            case .mcp: return true
            default: return true
            }
        }

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

        var titleHorizontalPadding: CGFloat {
            switch self {
            case .general, .dictation, .microphone, .transcription, .openAI, .mcp:
                return MacUI.SettingsViewMetrics.groupedFormTitleHorizontalPadding
            #if DEBUG
                case .shaderDebug: return MacUI.SettingsViewMetrics.detailHorizontalPadding
            #endif
            }
        }
    }

    struct MacSettingsView: View {
        @EnvironmentObject private var settingsShellViewModel: MacSettingsShellViewModel
        var onBack: (() -> Void)? = nil

        @StateObject private var dictionaryViewModel = DictionaryViewModel()
        @StateObject private var openAISettingsViewModel = MacOpenAISettingsViewModel()
        @State private var selectedTab: MacSettingsTab = .general
        @State private var titleScrollStore = MacSettingsTitleScrollStore()

        var body: some View {
            HStack(spacing: 0) {
                sidebarColumn
                detailColumn
            }
            .background {
                MacSettingsWindowChrome(
                    trafficLightLeading: MacUI.SettingsViewMetrics.trafficLightLeading,
                    trafficLightTop: MacUI.SettingsViewMetrics.trafficLightTop,
                    scrollerRevision: selectedTab.id
                )
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
            }
            .containerBackground(MacUI.Surfaces.hub, for: .window)
            .frame(minWidth: 720, minHeight: 520)
            .task {
                reloadStateFromPreferences()
                synchronizeSelection()
            }
            .onAppear {
                settingsShellViewModel.settingsDidAppear()
            }
            .onDisappear {
                settingsShellViewModel.settingsDidDisappear()
            }
            .onChange(of: selectedTab) { _, _ in
                titleScrollStore.reset()
            }
            .environment(\.macSettingsTitleScrollStore, titleScrollStore)
        }

        private var sidebarColumn: some View {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    Button {
                        onBack?()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 22, weight: .medium))
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(MacUI.Surfaces.ink)
                    .contentShape(Rectangle())
                    .opacity(onBack == nil ? 0 : 1)
                    .accessibilityLabel("Back to Stet")
                    .help("Back to Stet")
                }
                .padding(.leading, 16)
                .frame(height: MacUI.SettingsViewMetrics.headerHeight, alignment: .leading)
                sidebarNav
            }
            .frame(width: MacUI.SettingsViewMetrics.sidebarWidth)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(MacUI.Surfaces.hub.ignoresSafeArea())
        }

        private var brandHeader: some View {
            HStack(spacing: 8) {
                Image("stetMark")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(height: 14)
                    .accessibilityHidden(true)
                Text("Stet")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MacUI.Surfaces.ink)
            }
            .padding(.horizontal, MacUI.SettingsViewMetrics.sidebarHeaderHorizontalPadding)
        }

        private var sidebarNav: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: MacUI.SettingsViewMetrics.sidebarSectionSpacing) {
                    ForEach(MacSettingsSection.allCases) { section in
                        let tabs = visibleTabs.filter { $0.section == section }
                        if !tabs.isEmpty {
                            VStack(alignment: .leading, spacing: MacUI.SettingsViewMetrics.sidebarSectionItemSpacing) {
                                Text(LocalizedStringKey(section.title))
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(MacUI.Surfaces.ink)
                                    .padding(.horizontal, MacUI.SettingsViewMetrics.sidebarItemInset)

                                VStack(spacing: 2) {
                                    ForEach(tabs) { tab in
                                        sidebarRow(for: tab)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.top, 20)
                .padding(.horizontal, MacUI.SettingsViewMetrics.sidebarNavHorizontalPadding)
                .padding(.bottom, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
        }

        private func sidebarRow(for tab: MacSettingsTab) -> some View {
            let selected = tab == activeTab
            return Button {
                selectedTab = tab
            } label: {
                HStack(spacing: 0) {
                    Text(LocalizedStringKey(tab.title))
                        .font(.system(size: 13, weight: selected ? .medium : .regular))
                        .foregroundStyle(selected ? MacUI.Surfaces.ink : MacUI.Surfaces.ink.opacity(0.72))
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, MacUI.SettingsViewMetrics.sidebarItemInset)
                .padding(.vertical, MacUI.SettingsViewMetrics.sidebarRowVerticalPadding)
                .background {
                    RoundedRectangle(
                        cornerRadius: MacUI.SettingsViewMetrics.sidebarRowCornerRadius,
                        style: .continuous
                    )
                    .fill(selected ? MacUI.Surfaces.selection : Color.clear)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }

        private var detailColumn: some View {
            VStack(alignment: .leading, spacing: 0) {
                MacSettingsCollapsingTitle(
                    title: activeTab.title,
                    store: titleScrollStore,
                    horizontalPadding: activeTab.titleHorizontalPadding
                )

                selectedContent(for: activeTab)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .macSettingsScrollIndicator()
                    .id(activeTab.id)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(MacUI.Surfaces.paper.ignoresSafeArea())
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
                MacOpenAISettingsView(viewModel: openAISettingsViewModel)
            case .mcp:
                MacMCPSettingsView()
            #if DEBUG
                case .shaderDebug:
                    MacShaderDebugSettingsView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            #endif
            }
        }

        private var visibleTabs: [MacSettingsTab] {
            MacSettingsTab.allCases.filter(\.isAvailable)
        }

        private var activeTab: MacSettingsTab {
            if visibleTabs.contains(selectedTab) {
                return selectedTab
            }
            return visibleTabs.first ?? .general
        }

        private func reloadStateFromPreferences() {
            openAISettingsViewModel.load()
            dictionaryViewModel.load()
        }

        private func synchronizeSelection() {
            if visibleTabs.contains(selectedTab) {
                return
            }
            selectedTab = visibleTabs.first ?? .general
        }
    }
#endif
