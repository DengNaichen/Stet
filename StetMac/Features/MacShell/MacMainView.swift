#if os(macOS)
    import SwiftUI

    extension Notification.Name {
        static let stetOpenSettings = Notification.Name("stet.openSettings")
    }

    private enum MacMainTab: String, CaseIterable, Identifiable {
        case overview, history, dictionary, meetings, appearance

        var id: String { rawValue }
        var title: LocalizedStringKey {
            switch self {
            case .overview: "Overview"
            case .history: "History"
            case .dictionary: "Dictionary"
            case .meetings: "Meetings"
            case .appearance: "Appearance"
            }
        }
        var icon: String {
            switch self {
            case .overview: "house"
            case .history: "clock"
            case .dictionary: "text.book.closed"
            case .meetings: "calendar"
            case .appearance: "paintbrush"
            }
        }
    }

    struct MacMainView: View {
        @EnvironmentObject private var settingsShellViewModel: MacSettingsShellViewModel
        @StateObject private var dictionaryViewModel = DictionaryViewModel()
        @StateObject private var settingsNavState = MacSettingsNavigationState()
        @State private var selectedTab: MacMainTab = .overview
        @State private var showingSettings = false
        @State private var columnVisibility: NavigationSplitViewVisibility = .all

        var body: some View {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                sidebarContent
                    .navigationSplitViewColumnWidth(
                        min: 196,
                        ideal: MacUI.LinearMetrics.sidebarWidth,
                        max: 250
                    )
                    .toolbar(removing: .sidebarToggle)
            } detail: {
                detailContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(MacUI.LinearSurfaces.detailCanvas.ignoresSafeArea())
            }
            .background {
                MacSettingsWindowChrome(
                    trafficLightLeading: MacUI.SettingsViewMetrics.trafficLightLeading,
                    trafficLightTop: MacUI.SettingsViewMetrics.trafficLightTop,
                    scrollerRevision: showingSettings ? "settings-\(settingsNavState.activeTab.id)" : selectedTab.id
                )
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
            }
            .frame(
                minWidth: MacUI.LinearMetrics.windowMinWidth,
                minHeight: MacUI.LinearMetrics.windowMinHeight
            )
            .onReceive(NotificationCenter.default.publisher(for: .stetOpenSettings)) { _ in
                showingSettings = true
            }
            .onAppear {
                settingsShellViewModel.settingsDidAppear()
                dictionaryViewModel.load()
            }
            .onDisappear {
                settingsShellViewModel.settingsDidDisappear()
            }
        }

        @ViewBuilder
        private var sidebarContent: some View {
            if showingSettings {
                MacSettingsSidebarView(
                    state: settingsNavState,
                    onBack: { showingSettings = false }
                )
            } else {
                mainSidebar
            }
        }

        @ViewBuilder
        private var detailContent: some View {
            if showingSettings {
                MacSettingsDetailView(state: settingsNavState)
            } else {
                selectedContent
                    .id(selectedTab.id)
            }
        }

        private var mainSidebar: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        Image("stetMark")
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .frame(height: 15)
                            .accessibilityHidden(true)
                        Text("Stet")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(MacUI.Foreground.primary)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
                    .padding(.bottom, 14)

                    VStack(spacing: MacUI.LinearMetrics.sidebarRowGap) {
                        ForEach(MacMainTab.allCases) { tab in
                            LinearSidebarNavRow(
                                title: tab.title,
                                systemImage: tab.icon,
                                isSelected: selectedTab == tab
                            ) {
                                selectedTab = tab
                            }
                        }
                    }
                }
                .padding(.horizontal, MacUI.LinearMetrics.sidebarHorizontalPadding)
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .bottom, spacing: 4) {
                LinearSidebarNavRow(
                    title: "Settings",
                    systemImage: "gearshape",
                    isSelected: false,
                    shortcutHint: "⌘,"
                ) {
                    showingSettings = true
                }
                .keyboardShortcut(",", modifiers: .command)
                .padding(.horizontal, MacUI.LinearMetrics.sidebarHorizontalPadding)
                .padding(.bottom, 10)
            }
        }

        @ViewBuilder
        private var selectedContent: some View {
            switch selectedTab {
            case .overview: MacOverviewSettingsView()
            case .history: MacHistorySettingsView()
            case .dictionary: DictionaryView(viewModel: dictionaryViewModel)
            case .meetings: MacMeetingSettingsView()
            case .appearance: MacAppearanceSettingsView()
            }
        }
    }
#endif
