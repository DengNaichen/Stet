#if os(macOS)
    import StetCore
    import SwiftUI

    struct MacOverviewSettingsView: View {
        @Environment(\.scenePhase) private var scenePhase
        @StateObject private var viewModel = MacOverviewViewModel()

        var body: some View {
            LinearPageContainer(title: "Overview") {
                MacDictationUsageStatsView(summary: viewModel.usageSummary)
                MacDictationActivityHeatmapView(details: viewModel.activityDetails)
                MacDictationAppUsageView(apps: viewModel.appUsage)

                Text("Time saved is compared with typing at 40 WPM.")
                    .font(MacUI.LinearTypography.rowSubtitle)
                    .foregroundStyle(MacUI.LinearSurfaces.mutedInk)
                    .padding(.leading, 2)
            }
            .onReceive(NotificationCenter.default.publisher(for: .stetCloudDataDidChange)) { _ in viewModel.reload() }
            .task { viewModel.reload() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { viewModel.reload() } }
        }
    }
#endif
