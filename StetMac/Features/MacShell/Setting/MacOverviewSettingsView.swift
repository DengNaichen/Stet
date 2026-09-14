#if os(macOS)
    import SwiftUI
    import CoreData
    import Combine

    struct MacOverviewSettingsView: View {
        @Environment(\.scenePhase) private var scenePhase
        @State private var usageSummary = DictationUsageSummary.empty
        @State private var activityDetails: [Date: DictationDailySummary] = [:]
        @State private var appUsage: [DictationAppUsage] = []

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    MacDictationUsageStatsView(summary: usageSummary)
                    MacDictationActivityHeatmapView(details: activityDetails)
                    MacDictationAppUsageView(apps: appUsage)

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
            .task { reload() }
            .onReceive(
                NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange).receive(on: RunLoop.main)
            ) {
                _ in reload()
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .dictationStatisticsDidChange).receive(on: RunLoop.main)
            ) {
                _ in reload()
            }
            .onChange(of: scenePhase) { _, phase in if phase == .active { reload() } }
        }

        private func reload() {
            usageSummary = DictationStatsModel.shared.usageSummary()
            activityDetails = DictationStatsModel.shared.activityDetails()
            appUsage = DictationStatsModel.shared.appUsage()
        }
    }
#endif
