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
        @StateObject private var titleScrollStore = MacSettingsTitleScrollStore()

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
            .frame(minWidth: MacUI.SettingsViewMetrics.minimumWidth, minHeight: MacUI.SettingsViewMetrics.minimumHeight)
            .task {
                reloadStateFromPreferences()
                synchronizeSelection()
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
                            .font(MacUI.Typography.backButton)
                            .frame(
                                width: MacUI.SettingsViewMetrics.backButtonSize,
                                height: MacUI.SettingsViewMetrics.backButtonSize)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(MacUI.Surfaces.ink)
                    .contentShape(Rectangle())
                    .opacity(onBack == nil ? 0 : 1)
                    .accessibilityLabel("Back to Stet")
                    .help("Back to Stet")
                }
                .padding(.leading, MacUI.SettingsViewMetrics.backButtonLeadingPadding)
                .frame(height: MacUI.SettingsViewMetrics.headerHeight, alignment: .leading)
                sidebarNav
            }
            .frame(width: MacUI.SettingsViewMetrics.sidebarWidth)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(MacUI.Surfaces.hub.ignoresSafeArea())
        }

        private var brandHeader: some View {
            HStack(spacing: MacUI.SettingsViewMetrics.controlSpacing) {
                Image("stetMark")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(height: MacUI.SettingsViewMetrics.brandMarkHeight)
                    .accessibilityHidden(true)
                Text("Stet")
                    .font(MacUI.Typography.brand)
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
                                    .font(MacUI.Typography.sidebarSection)
                                    .foregroundStyle(MacUI.Surfaces.ink)
                                    .padding(.horizontal, MacUI.SettingsViewMetrics.sidebarItemInset)

                                VStack(spacing: MacUI.SettingsViewMetrics.sidebarRowSpacing) {
                                    ForEach(tabs) { tab in
                                        sidebarRow(for: tab)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.top, MacUI.SettingsViewMetrics.sidebarVerticalPadding)
                .padding(.horizontal, MacUI.SettingsViewMetrics.sidebarNavHorizontalPadding)
                .padding(.bottom, MacUI.SettingsViewMetrics.sidebarVerticalPadding)
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
                        .font(selected ? MacUI.Typography.selectedSidebarItem : MacUI.Typography.sidebarItem)
                        .foregroundStyle(selected ? MacUI.Surfaces.ink : MacUI.Surfaces.secondaryInk)
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
