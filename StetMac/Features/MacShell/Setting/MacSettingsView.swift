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
                return "How Stet lives on this Mac."
            case .appearance:
                return "The capsule is the product. Everything else stays quiet."
            case .dictation:
                return "One shortcut to speak. Then the words land."
            case .microphone:
                return "Choose the input. Test it before you need it."
            case .transcription:
                return "On-device engines. Download what you actually use."
            case .voice:
                return "Passive listening and speaker profiles."
            case .meetings:
                return "Record the room. Open the folder when you need it."
            case .openAI:
                return "Optional pass after transcription. Off is a valid choice."
            case .dictionary:
                return "Names and terms the engine should already know."
            case .history:
                return "Past dictations. Not a preference — a library."
            #if DEBUG
                case .shaderDebug:
                    return "Large shader preview and color input controls."
            #endif
            }
        }
    }

    struct MacSettingsView: View {
        @EnvironmentObject private var settingsShellViewModel: MacSettingsShellViewModel

        @StateObject private var dictionaryViewModel = DictionaryViewModel()
        @StateObject private var openAISettingsViewModel = MacOpenAISettingsViewModel()
        @State private var selectedTab: MacSettingsTab = .general

        var body: some View {
            HStack(spacing: 0) {
                sidebarColumn
                detailColumn
            }
            .background {
                MacSettingsWindowChrome(
                    trafficLightLeading: MacUI.SettingsViewMetrics.trafficLightLeading,
                    trafficLightTop: MacUI.SettingsViewMetrics.trafficLightTop
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
        }

        private var sidebarColumn: some View {
            VStack(alignment: .leading, spacing: 0) {
                brandHeader
                    .frame(height: MacUI.SettingsViewMetrics.headerHeight, alignment: .leading)
                sidebarNav
            }
            .frame(width: MacUI.SettingsViewMetrics.sidebarWidth)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(MacUI.Surfaces.hub.ignoresSafeArea())
        }

        private var brandHeader: some View {
            HStack(spacing: 8) {
                StetWaveMark()
                    .stroke(
                        MacUI.Brand.orange,
                        style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round)
                    )
                    .frame(width: 16, height: 10)
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
            .scrollIndicators(.never)
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
                Text(LocalizedStringKey(activeTab.title))
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(MacUI.Surfaces.ink)
                    .frame(
                        maxWidth: .infinity,
                        minHeight: MacUI.SettingsViewMetrics.headerHeight,
                        alignment: .leading
                    )

                Text(LocalizedStringKey(activeTab.subtitle))
                    .font(.system(size: 13))
                    .foregroundStyle(MacUI.Surfaces.mute)
                    .padding(.top, 8)
                    .padding(.bottom, 28)

                selectedContent(for: activeTab)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .scrollIndicators(.never)
            }
            .padding(.horizontal, MacUI.SettingsViewMetrics.detailHorizontalPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(MacUI.Surfaces.paper.ignoresSafeArea())
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
