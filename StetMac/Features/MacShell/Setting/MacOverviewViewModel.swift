#if os(macOS)
    import Combine
    import Combine
    import Foundation

    @MainActor
    final class MacOverviewViewModel: ObservableObject {
        @Published private(set) var usageSummary = DictationUsageSummary.empty
        @Published private(set) var activityDetails: [Date: DictationDailySummary] = [:]
        @Published private(set) var appUsage: [DictationAppUsage] = []

        private let stats: DictationStatsModel

        init(stats: DictationStatsModel = .shared) {
            self.stats = stats
        }

        func reload() {
            usageSummary = stats.usageSummary()
            activityDetails = stats.activityDetails()
            appUsage = stats.appUsage()
        }
    }
#endif
