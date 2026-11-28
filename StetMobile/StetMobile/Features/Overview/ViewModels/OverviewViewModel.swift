import Combine
import Foundation
import StetCore

enum OverviewTimeRange: String, CaseIterable, Identifiable, Sendable {
    case oneMonth
    case twoMonths
    case threeMonths
    case sixMonths
    case oneYear

    var id: String { rawValue }

    var shortTitle: String {
        switch self {
        case .oneMonth: "1M"
        case .twoMonths: "2M"
        case .threeMonths: "3M"
        case .sixMonths: "6M"
        case .oneYear: "1Y"
        }
    }

    var weeksCount: Int {
        switch self {
        case .oneMonth: 5
        case .twoMonths: 9
        case .threeMonths: 13
        case .sixMonths: 26
        case .oneYear: 52
        }
    }

    var daySpan: Int {
        switch self {
        case .oneMonth: 30
        case .twoMonths: 60
        case .threeMonths: 90
        case .sixMonths: 180
        case .oneYear: 365
        }
    }

    func startDate(relativeTo now: Date = Date(), calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: -(daySpan - 1), to: today) ?? today
    }
}

@MainActor
final class OverviewViewModel: ObservableObject {
    @Published var selectedRange: OverviewTimeRange = .twoMonths {
        didSet {
            guard selectedRange != oldValue else { return }
            reloadStatsForSelectedRange()
        }
    }

    @Published private(set) var usageSummary: DictationUsageSummary = .empty
    @Published private(set) var activityDetails: [Date: DictationDailySummary] = [:]
    @Published private(set) var appUsage: [DictationAppUsage] = []

    private let statsModel: DictationStatsModel
    private var cancellables: Set<AnyCancellable> = []

    init(
        statsModel: DictationStatsModel = .shared,
        notificationCenter: NotificationCenter = .default
    ) {
        self.statsModel = statsModel

        notificationCenter.publisher(for: .stetCloudDataDidChange)
            .sink { [weak self] _ in
                self?.reload()
            }
            .store(in: &cancellables)
    }

    func reload() {
        activityDetails = statsModel.activityDetails()
        appUsage = statsModel.appUsage(limit: 5)
        reloadStatsForSelectedRange()
    }

    private func reloadStatsForSelectedRange() {
        let since = selectedRange.startDate()
        usageSummary = statsModel.usageSummary(since: since)
    }
}
