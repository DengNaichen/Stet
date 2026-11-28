import Foundation
import SwiftData

@Model
public final class DictationSessionRecord {
    public var id: UUID = UUID()
    public var sourcePlatform: String? = nil
    public var startedAt: Date = Date()
    public var durationSeconds: Double = 0
    public var wordCount: Int = 0
    public var targetBundleID: String? = nil
    public var targetAppName: String? = nil

    public init(
        startedAt: Date,
        durationSeconds: Double,
        wordCount: Int,
        targetBundleID: String? = nil,
        targetAppName: String? = nil,
        sourcePlatform: String? = nil
    ) {
        self.sourcePlatform = sourcePlatform
        self.startedAt = startedAt
        self.durationSeconds = durationSeconds
        self.wordCount = wordCount
        self.targetBundleID = targetBundleID
        self.targetAppName = targetAppName
    }
}

public struct DictationAppUsage: Equatable, Identifiable, Sendable {
    public static let otherID = "other"
    public static let otherName = "Other"

    public var id: String
    public var bundleID: String?
    public var name: String
    public var sessionCount: Int
    public var wordCount: Int
    public var durationSeconds: TimeInterval
    public var share: Double

    public var formattedWordCount: String {
        DictationUsageSummary.formatCompactCount(wordCount)
    }

    public var formattedSessionCount: String {
        sessionCount == 1 ? "1 session" : "\(sessionCount) sessions"
    }
}

public struct DictationDailySummary: Equatable, Sendable {
    public var wordCount: Int
    public var totalDuration: TimeInterval

    public var timeSaved: TimeInterval {
        guard wordCount > 0 else { return 0 }
        let typingDuration = Double(wordCount) / DictationUsageSummary.assumedTypingWordsPerMinute * 60
        return max(0, typingDuration - totalDuration)
    }

    public var formattedWordCount: String {
        DictationUsageSummary.formatCompactCount(wordCount)
    }

    public var formattedTimeSaved: String {
        DictationUsageSummary.formatDuration(timeSaved)
    }
}

public struct DictationUsageSummary: Equatable, Sendable {
    public static let assumedTypingWordsPerMinute = 40.0
    public static let empty = DictationUsageSummary(sessionCount: 0, totalDuration: 0, wordCount: 0)

    public var sessionCount: Int
    public var totalDuration: TimeInterval
    public var wordCount: Int

    public init(sessionCount: Int, totalDuration: TimeInterval, wordCount: Int) {
        self.sessionCount = sessionCount
        self.totalDuration = totalDuration
        self.wordCount = wordCount
    }

    public var averageWordsPerMinute: Double? {
        guard totalDuration > 0, wordCount > 0 else { return nil }
        return Double(wordCount) / (totalDuration / 60)
    }

    public var timeSaved: TimeInterval {
        guard wordCount > 0 else { return 0 }
        let typingDuration = Double(wordCount) / Self.assumedTypingWordsPerMinute * 60
        return max(0, typingDuration - totalDuration)
    }

    public var formattedDuration: String {
        Self.formatDuration(totalDuration)
    }

    public var formattedWordCount: String {
        Self.formatCompactCount(wordCount)
    }

    public var formattedTimeSaved: String {
        Self.formatDuration(timeSaved)
    }

    public var formattedWordsPerMinute: String {
        guard let averageWordsPerMinute else { return "—" }
        return "\(Int(averageWordsPerMinute.rounded()))"
    }

    fileprivate static func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration.rounded()))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60

        if hours > 0, minutes > 0 {
            return "\(hours) hr \(minutes) min"
        }
        if hours > 0 {
            return "\(hours) hr"
        }
        if minutes > 0 {
            return "\(minutes) min"
        }
        return "\(seconds) sec"
    }

    public static func formatCompactCount(_ count: Int) -> String {
        switch count {
        case 1_000_000...:
            return compact(Double(count) / 1_000_000, suffix: "M")
        case 1_000...:
            return compact(Double(count) / 1_000, suffix: "K")
        default:
            return "\(count)"
        }
    }

    private static func compact(_ value: Double, suffix: String) -> String {
        let roundedToOneDecimal = (value * 10).rounded() / 10
        if roundedToOneDecimal >= 100 || roundedToOneDecimal == roundedToOneDecimal.rounded() {
            return "\(Int(roundedToOneDecimal.rounded()))\(suffix)"
        }
        return String(format: "%.1f\(suffix)", roundedToOneDecimal)
    }
}

public struct DictationStatsModel: Sendable {
    public static let shared = DictationStatsModel()

    nonisolated private let modelContainer: ModelContainer?

    public nonisolated init(modelContainer: ModelContainer? = StetCloudDataContainer.shared.modelContainer) {
        self.modelContainer = modelContainer
    }

    public nonisolated func record(
        startedAt: Date,
        durationSeconds: Double,
        wordCount: Int,
        targetBundleID: String? = nil,
        targetAppName: String? = nil,
        sourcePlatform: String? = nil
    ) {
        guard let context = modelContext else { return }
        context.insert(
            DictationSessionRecord(
                startedAt: startedAt,
                durationSeconds: durationSeconds,
                wordCount: wordCount,
                targetBundleID: Self.normalized(targetBundleID),
                targetAppName: Self.normalized(targetAppName),
                sourcePlatform: sourcePlatform
            )
        )
        try? context.save()
    }

    public struct HistoryTranscript: Sendable {
        public var endedAt: Date
        public var text: String

        public init(endedAt: Date, text: String) {
            self.endedAt = endedAt
            self.text = text
        }
    }

    public struct RecountResult: Equatable, Sendable {
        public var updated: Int
        public var unmatched: Int

        public init(updated: Int, unmatched: Int) {
            self.updated = updated
            self.unmatched = unmatched
        }
    }

    /// Rewrites `wordCount` for sessions whose end time matches a history transcript.
    @discardableResult
    public nonisolated func recountDisplayUnits(
        from history: [HistoryTranscript],
        matchWindow: TimeInterval = 3
    ) -> RecountResult {
        guard let context = modelContext else {
            return RecountResult(updated: 0, unmatched: history.count)
        }
        var available = (try? context.fetch(FetchDescriptor<DictationSessionRecord>())) ?? []
        var updated = 0
        var unmatched = 0

        for item in history {
            let units = DictationWordCounter.displayUnits(in: item.text)
            guard units > 0 else {
                unmatched += 1
                continue
            }
            guard let index = bestSessionIndex(for: item.endedAt, in: available, matchWindow: matchWindow)
            else {
                unmatched += 1
                continue
            }
            available[index].wordCount = units
            available.remove(at: index)
            updated += 1
        }

        if updated > 0 {
            try? context.save()
        }
        return RecountResult(updated: updated, unmatched: unmatched)
    }

    public nonisolated func usageSummary(since date: Date? = nil) -> DictationUsageSummary {
        let sessions = fetchSessions(since: date)
        return DictationUsageSummary(
            sessionCount: sessions.count,
            totalDuration: sessions.reduce(0) { $0 + $1.durationSeconds },
            wordCount: sessions.reduce(0) { $0 + $1.wordCount }
        )
    }

    public nonisolated func todaySessionCount() -> Int {
        usageSummary(since: startOfToday()).sessionCount
    }

    public nonisolated func todayTotalDuration() -> TimeInterval {
        usageSummary(since: startOfToday()).totalDuration
    }

    public nonisolated func allTimeSessionCount() -> Int {
        usageSummary().sessionCount
    }

    public nonisolated func allTimeTotalDuration() -> TimeInterval {
        usageSummary().totalDuration
    }

    public nonisolated func todayTotalWordCount() -> Int {
        usageSummary(since: startOfToday()).wordCount
    }

    public nonisolated func allTimeTotalWordCount() -> Int {
        usageSummary().wordCount
    }

    public nonisolated func activityContributions(
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [Date: Double] {
        activityDetails(now: now, calendar: calendar).mapValues { Double($0.wordCount) }
    }

    public nonisolated func activityDetails(
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [Date: DictationDailySummary] {
        let today = calendar.startOfDay(for: now)
        let since = calendar.date(byAdding: .day, value: -364, to: today)
        let sessions = fetchSessions(since: since)
        var totals: [Date: (wordCount: Int, duration: TimeInterval)] = [:]
        for session in sessions {
            let day = calendar.startOfDay(for: session.startedAt)
            totals[day, default: (0, 0)].wordCount += session.wordCount
            totals[day, default: (0, 0)].duration += session.durationSeconds
        }
        return totals.mapValues {
            DictationDailySummary(wordCount: $0.wordCount, totalDuration: $0.duration)
        }
    }

    public nonisolated func appUsage(limit: Int = 6) -> [DictationAppUsage] {
        let sessions = fetchSessions(since: nil)
        guard !sessions.isEmpty else { return [] }

        struct Accumulator {
            var bundleID: String?
            var name: String
            var sessionCount: Int
            var wordCount: Int
            var durationSeconds: TimeInterval
        }

        var grouped: [String: Accumulator] = [:]
        for session in sessions {
            let bundleID = Self.normalized(session.targetBundleID)
            let appName = Self.normalized(session.targetAppName)
            let key: String
            if let bundleID {
                key = bundleID
            } else if let appName {
                key = "name:\(appName)"
            } else {
                continue
            }

            var current =
                grouped[key]
                ?? Accumulator(
                    bundleID: bundleID,
                    name: appName ?? bundleID ?? key,
                    sessionCount: 0,
                    wordCount: 0,
                    durationSeconds: 0
                )
            current.sessionCount += 1
            current.wordCount += session.wordCount
            current.durationSeconds += session.durationSeconds
            if let appName {
                current.name = appName
            }
            if current.bundleID == nil {
                current.bundleID = bundleID
            }
            grouped[key] = current
        }

        guard !grouped.isEmpty else { return [] }

        let totalWords = grouped.values.reduce(0) { $0 + $1.wordCount }
        let totalSessions = grouped.values.reduce(0) { $0 + $1.sessionCount }
        let ranked = grouped.map { key, value in
            DictationAppUsage(
                id: key,
                bundleID: value.bundleID,
                name: value.name,
                sessionCount: value.sessionCount,
                wordCount: value.wordCount,
                durationSeconds: value.durationSeconds,
                share: Self.share(
                    words: value.wordCount,
                    totalWords: totalWords,
                    sessions: value.sessionCount,
                    totalSessions: totalSessions
                )
            )
        }
        .sorted { lhs, rhs in
            if lhs.wordCount != rhs.wordCount { return lhs.wordCount > rhs.wordCount }
            if lhs.sessionCount != rhs.sessionCount { return lhs.sessionCount > rhs.sessionCount }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        guard ranked.count > limit else { return ranked }

        let top = Array(ranked.prefix(limit))
        let rest = ranked.dropFirst(limit)
        let otherWords = rest.reduce(0) { $0 + $1.wordCount }
        let otherSessions = rest.reduce(0) { $0 + $1.sessionCount }
        let otherDuration = rest.reduce(0) { $0 + $1.durationSeconds }
        let other = DictationAppUsage(
            id: DictationAppUsage.otherID,
            bundleID: nil,
            name: DictationAppUsage.otherName,
            sessionCount: otherSessions,
            wordCount: otherWords,
            durationSeconds: otherDuration,
            share: Self.share(
                words: otherWords,
                totalWords: totalWords,
                sessions: otherSessions,
                totalSessions: totalSessions
            )
        )
        return top + [other]
    }

    public nonisolated static func makeInMemoryModelContainer() throws -> ModelContainer {
        try StetCloudDataContainer.makeInMemoryContainer()
    }

    public nonisolated static func makePersistentModelContainer(
        appSupportDirectory: URL? = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first,
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "NaichengDeng.Stet"
    ) throws -> ModelContainer {
        guard let appSupportDirectory else { throw CocoaError(.fileNoSuchFile) }
        return try StetCloudDataContainer.makePersistentContainer(
            appSupportDirectory: appSupportDirectory, bundleIdentifier: bundleIdentifier)
    }

    nonisolated private var modelContext: ModelContext? {
        modelContainer.map { ModelContext($0) }
    }

    nonisolated private func fetchSessions(since date: Date?) -> [DictationSessionRecord] {
        guard let context = modelContext else { return [] }
        var descriptor = FetchDescriptor<DictationSessionRecord>()
        if let date {
            descriptor.predicate = #Predicate { $0.startedAt >= date }
        }
        var seen = Set<UUID>()
        return ((try? context.fetch(descriptor)) ?? []).filter { seen.insert($0.id).inserted }
    }

    nonisolated private func bestSessionIndex(
        for endedAt: Date,
        in sessions: [DictationSessionRecord],
        matchWindow: TimeInterval
    ) -> Int? {
        var best: (index: Int, delta: TimeInterval)?
        for (index, session) in sessions.enumerated() {
            let sessionEnd = session.startedAt.addingTimeInterval(session.durationSeconds)
            let delta = abs(sessionEnd.timeIntervalSince(endedAt))
            guard delta <= matchWindow else { continue }
            if best == nil || delta < best!.delta {
                best = (index, delta)
            }
        }
        return best?.index
    }

    nonisolated private func startOfToday() -> Date {
        Calendar.current.startOfDay(for: Date())
    }

    nonisolated private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    nonisolated private static func share(
        words: Int,
        totalWords: Int,
        sessions: Int,
        totalSessions: Int
    ) -> Double {
        if totalWords > 0 {
            return Double(words) / Double(totalWords)
        }
        if totalSessions > 0 {
            return Double(sessions) / Double(totalSessions)
        }
        return 0
    }

}
