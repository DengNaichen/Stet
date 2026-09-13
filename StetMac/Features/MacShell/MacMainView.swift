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
        @EnvironmentObject private var appModel: MacAppModel
        @EnvironmentObject private var compatibilityStore: AppCompatibilityStore
        @EnvironmentObject private var rewriteModelCatalogStore: RewriteModelCatalogStore
        @EnvironmentObject private var settingsShellViewModel: MacSettingsShellViewModel
        @EnvironmentObject private var appUpdateManager: AppUpdateManager
        @StateObject private var dictionaryViewModel = DictionaryViewModel()
        @State private var selectedTab: MacMainTab = .overview
        @State private var showingSettings = false

        var body: some View {
            Group {
                if showingSettings {
                    MacSettingsView(onBack: { showingSettings = false })
                } else {
                    mainContent
                }
            }
            .background(MacUI.Surfaces.paper.ignoresSafeArea())
            .containerBackground(MacUI.Surfaces.hub, for: .window)
            .frame(minWidth: 720, minHeight: 520)
            .onReceive(NotificationCenter.default.publisher(for: .stetOpenSettings)) { _ in
                showingSettings = true
            }
            .onChange(of: showingSettings) { _, value in
                if !value { selectedTab = .overview }
            }
        }

        private var mainContent: some View {
            HStack(spacing: 0) {
                sidebar
                detail
            }
        }

        private var sidebar: some View {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Image("stetMark").resizable().scaledToFit().frame(height: 14)
                    Text("Stet").font(.system(size: 13, weight: .semibold))
                }
                .padding(.horizontal, 24)
                .frame(height: 40)

                VStack(spacing: 3) {
                    ForEach(MacMainTab.allCases) { tab in
                        Button {
                            selectedTab = tab
                        } label: {
                            Label(tab.title, systemImage: tab.icon)
                                .font(.system(size: 13, weight: tab == selectedTab ? .medium : .regular))
                                .foregroundStyle(
                                    tab == selectedTab ? MacUI.Surfaces.ink : MacUI.Surfaces.ink.opacity(0.72)
                                )
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    tab == selectedTab ? MacUI.Surfaces.selection : .clear,
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 20)

                Spacer()

                Button {
                    showingSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                        .font(.system(size: 12))
                        .foregroundStyle(MacUI.Surfaces.ink.opacity(0.72))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.bottom, 16)
            }
            .frame(width: MacUI.SettingsViewMetrics.sidebarWidth)
            .background(MacUI.Surfaces.hub)
        }

        private var detail: some View {
            VStack(alignment: .leading, spacing: 0) {
                Text(selectedTab.title)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(MacUI.Surfaces.ink)
                    .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
                    .padding(.horizontal, 36)
                selectedContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .background(MacUI.Surfaces.paper)
        }

        @ViewBuilder private var selectedContent: some View {
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
