#if os(macOS)
    import SwiftUI

    struct MacOverviewSettingsView: View {
        @Environment(\.scenePhase) private var scenePhase
        @StateObject private var viewModel = MacOverviewViewModel()

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    MacDictationUsageStatsView(summary: viewModel.usageSummary)
                    MacDictationActivityHeatmapView(details: viewModel.activityDetails)
                    MacDictationAppUsageView(apps: viewModel.appUsage)

                    Text("Time saved is compared with typing at 40 WPM.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, MacUI.SettingsViewMetrics.detailHorizontalPadding)
                .padding(.top, 8)
                .padding(.bottom, MacUI.SettingsViewMetrics.formBottomPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .macSettingsTracksTitleScroll()
            .task { viewModel.reload() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { viewModel.reload() } }
        }
    }
#endif
