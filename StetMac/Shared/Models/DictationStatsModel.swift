#if os(macOS)
    import Foundation
    import SwiftData
    import os

    nonisolated private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.openwhispr.Stet",
        category: "general"
    )

    nonisolated private let sharedDictationStatsModelContainer: ModelContainer? = {
        do {
            return try DictationStatsModel.makePersistentModelContainer()
        } catch {
            logger.error("Failed to create DictationStatsModel container. error=\(error)")
            return nil
        }
    }()

    @Model
    final class DictationSessionRecord {
        var startedAt: Date = Date()
        var durationSeconds: Double = 0
        var wordCount: Int = 0
        var targetBundleID: String? = nil
        var targetAppName: String? = nil

        init(
            startedAt: Date,
            durationSeconds: Double,
            wordCount: Int,
            targetBundleID: String? = nil,
            targetAppName: String? = nil
        ) {
            self.startedAt = startedAt
            self.durationSeconds = durationSeconds
            self.wordCount = wordCount
            self.targetBundleID = targetBundleID
            self.targetAppName = targetAppName
        }
    }

    struct DictationAppUsage: Equatable, Identifiable, Sendable {
        static let unknownID = "unknown"
        static let otherID = "other"
        static let unknownName = "Unknown"
        static let otherName = "Other"

        var id: String
        var bundleID: String?
        var name: String
        var sessionCount: Int
        var wordCount: Int
        var durationSeconds: TimeInterval
        var share: Double

        var formattedWordCount: String {
            DictationUsageSummary.formatCompactCount(wordCount)
        }

        var formattedSessionCount: String {
            sessionCount == 1 ? "1 session" : "\(sessionCount) sessions"
        }
    }

    struct DictationUsageSummary: Equatable, Sendable {
        static let assumedTypingWordsPerMinute = 40.0
        static let empty = DictationUsageSummary(sessionCount: 0, totalDuration: 0, wordCount: 0)

        var sessionCount: Int
        var totalDuration: TimeInterval
        var wordCount: Int

        var averageWordsPerMinute: Double? {
            guard totalDuration > 0, wordCount > 0 else { return nil }
            return Double(wordCount) / (totalDuration / 60)
        }

        var timeSaved: TimeInterval {
            guard wordCount > 0 else { return 0 }
            let typingDuration = Double(wordCount) / Self.assumedTypingWordsPerMinute * 60
            return max(0, typingDuration - totalDuration)
        }

        var formattedDuration: String {
            Self.formatDuration(totalDuration)
        }

        var formattedWordCount: String {
            Self.formatCompactCount(wordCount)
        }

        var formattedTimeSaved: String {
            Self.formatDuration(timeSaved)
        }

        var formattedWordsPerMinute: String {
            guard let averageWordsPerMinute else { return "—" }
            return "\(Int(averageWordsPerMinute.rounded()))"
        }

        private static func formatDuration(_ duration: TimeInterval) -> String {
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

        static func formatCompactCount(_ count: Int) -> String {
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

    struct DictationStatsModel: @unchecked Sendable {
        static let shared = DictationStatsModel()

        nonisolated private let modelContainer: ModelContainer?

        nonisolated init(modelContainer: ModelContainer? = sharedDictationStatsModelContainer) {
            self.modelContainer = modelContainer
        }

        nonisolated func record(
            startedAt: Date,
            durationSeconds: Double,
            wordCount: Int,
            targetBundleID: String? = nil,
            targetAppName: String? = nil
        ) {
            guard let context = modelContext else { return }
            context.insert(
                DictationSessionRecord(
                    startedAt: startedAt,
                    durationSeconds: durationSeconds,
                    wordCount: wordCount,
                    targetBundleID: Self.normalized(targetBundleID),
                    targetAppName: Self.normalized(targetAppName)
                )
            )
            try? context.save()
        }

        nonisolated func usageSummary(since date: Date? = nil) -> DictationUsageSummary {
            let sessions = fetchSessions(since: date)
            return DictationUsageSummary(
                sessionCount: sessions.count,
                totalDuration: sessions.reduce(0) { $0 + $1.durationSeconds },
                wordCount: sessions.reduce(0) { $0 + $1.wordCount }
            )
        }

        nonisolated func todaySessionCount() -> Int {
            usageSummary(since: startOfToday()).sessionCount
        }

        nonisolated func todayTotalDuration() -> TimeInterval {
            usageSummary(since: startOfToday()).totalDuration
        }

        nonisolated func allTimeSessionCount() -> Int {
            usageSummary().sessionCount
        }

        nonisolated func allTimeTotalDuration() -> TimeInterval {
            usageSummary().totalDuration
        }

        nonisolated func todayTotalWordCount() -> Int {
            usageSummary(since: startOfToday()).wordCount
        }

        nonisolated func allTimeTotalWordCount() -> Int {
            usageSummary().wordCount
        }

        nonisolated func activityContributions(
            now: Date = Date(),
            calendar: Calendar = .current
        ) -> [Date: Double] {
            let today = calendar.startOfDay(for: now)
            let since = calendar.date(byAdding: .day, value: -364, to: today)
            let sessions = fetchSessions(since: since)
            var totals: [Date: Double] = [:]
            for session in sessions {
                let day = calendar.startOfDay(for: session.startedAt)
                totals[day, default: 0] += Double(session.wordCount)
            }
            return totals
        }

        nonisolated func appUsage(limit: Int = 6) -> [DictationAppUsage] {
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
                    key = DictationAppUsage.unknownID
                }

                var current =
                    grouped[key]
                    ?? Accumulator(
                        bundleID: bundleID,
                        name: appName ?? DictationAppUsage.unknownName,
                        sessionCount: 0,
                        wordCount: 0,
                        durationSeconds: 0
                    )
                current.sessionCount += 1
                current.wordCount += session.wordCount
                current.durationSeconds += session.durationSeconds
                if current.name == DictationAppUsage.unknownName, let appName {
                    current.name = appName
                }
                if current.bundleID == nil {
                    current.bundleID = bundleID
                }
                grouped[key] = current
            }

            let totalWords = sessions.reduce(0) { $0 + $1.wordCount }
            let totalSessions = sessions.count
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

        nonisolated static func makeInMemoryModelContainer() throws -> ModelContainer {
            let schema = Schema([DictationSessionRecord.self])
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return try ModelContainer(for: schema, configurations: [configuration])
        }

        nonisolated static func makePersistentModelContainer(
            appSupportDirectory: URL? = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            ).first,
            bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "NaichengDeng.Stet"
        ) throws -> ModelContainer {
            let schema = Schema([DictationSessionRecord.self])
            let configuration = ModelConfiguration(
                schema: schema,
                url: try persistentStoreURL(
                    appSupportDirectory: appSupportDirectory,
                    bundleIdentifier: bundleIdentifier
                )
            )
            return try ModelContainer(for: schema, configurations: [configuration])
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
            return (try? context.fetch(descriptor)) ?? []
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

        nonisolated private static func persistentStoreURL(
            appSupportDirectory: URL?,
            bundleIdentifier: String
        ) throws -> URL {
            guard let appSupportDirectory else { throw CocoaError(.fileNoSuchFile) }
            let directoryURL =
                appSupportDirectory
                .appendingPathComponent(bundleIdentifier, isDirectory: true)
                .appendingPathComponent("SwiftData", isDirectory: true)
            try FileManager.default.createDirectory(
                at: directoryURL, withIntermediateDirectories: true, attributes: nil
            )
            return directoryURL.appendingPathComponent("DictationStats.store")
        }
    }
#endif
