#if os(macOS)
    import Combine
    import SwiftUI

    extension Notification.Name {
        static let stetOpenSettings = Notification.Name("stet.openSettings")
    }

    enum MacMainTab: String, CaseIterable, Identifiable {
        case overview, history, dictionary, meetings

        var id: String { rawValue }
        var title: LocalizedStringKey {
            switch self {
            case .overview: "Overview"
            case .history: "History"
            case .dictionary: "Dictionary"
            case .meetings: "Meetings"
            }
        }
        var icon: String {
            switch self {
            case .overview: "house"
            case .history: "clock"
            case .dictionary: "text.book.closed"
            case .meetings: "calendar"
            }
        }
    }

    @MainActor
    final class MacMainNavigationState: ObservableObject {
        @Published var selectedTab: MacMainTab = .overview
        @Published var showingSettings = false
        let settingsNavState: MacSettingsNavigationState
        private var settingsCancellable: AnyCancellable?

        init(settingsNavState: MacSettingsNavigationState? = nil) {
            let resolvedSettingsNavState = settingsNavState ?? MacSettingsNavigationState()
            self.settingsNavState = resolvedSettingsNavState
            self.settingsCancellable = resolvedSettingsNavState.objectWillChange.sink { [weak self] _ in
                self?.objectWillChange.send()
            }
        }

        func openSettings() {
            showingSettings = true
        }

        func openSettings(to tab: MacSettingsTab, section: MacSettingsTargetSection? = nil) {
            settingsNavState.navigate(to: tab, section: section)
            showingSettings = true
        }

        func backToApp() {
            settingsNavState.clearFilter()
            showingSettings = false
        }
    }

    struct MacMainView: View {
        @EnvironmentObject private var settingsShellViewModel: MacSettingsShellViewModel
        @StateObject private var dictionaryViewModel = DictionaryViewModel()
        @StateObject private var navigationState = MacMainNavigationState()
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
                    scrollerRevision: navigationState.showingSettings
                        ? "settings-\(navigationState.settingsNavState.activeTab.id)"
                        : navigationState.selectedTab.id
                )
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
            }
            .frame(
                minWidth: MacUI.LinearMetrics.windowMinWidth,
                minHeight: MacUI.LinearMetrics.windowMinHeight
            )
            .onReceive(NotificationCenter.default.publisher(for: .stetOpenSettings)) { _ in
                navigationState.openSettings()
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
            if navigationState.showingSettings {
                MacSettingsSidebarView(
                    state: navigationState.settingsNavState,
                    onBack: { navigationState.backToApp() }
                )
            } else {
                mainSidebar
            }
        }

        @ViewBuilder
        private var detailContent: some View {
            if navigationState.showingSettings {
                MacSettingsDetailView(state: navigationState.settingsNavState)
            } else {
                selectedContent
                    .id(navigationState.selectedTab.id)
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
                                isSelected: navigationState.selectedTab == tab
                            ) {
                                navigationState.selectedTab = tab
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
                    navigationState.openSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
                .padding(.horizontal, MacUI.LinearMetrics.sidebarHorizontalPadding)
                .padding(.bottom, 10)
            }
        }

        @ViewBuilder
        private var selectedContent: some View {
            switch navigationState.selectedTab {
            case .overview:
                MacOverviewSettingsView()
            case .history:
                MacHistorySettingsView()
            case .dictionary:
                DictionaryView(viewModel: dictionaryViewModel)
            case .meetings:
                MacMeetingSettingsView(onOpenShortcutSettings: {
                    navigationState.openSettings(to: .dictation, section: .shortcuts)
                })
            }
        }
    }
#endif
