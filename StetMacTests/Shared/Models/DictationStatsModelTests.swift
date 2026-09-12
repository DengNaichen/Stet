#if os(macOS)
    import Foundation
    import Testing

    @testable import Stet

    @Suite("Dictation Stats Model", .serialized)
    struct DictationStatsModelTests {
        @Test func recordsSessionsIntoAnAllTimeSummary() throws {
            let model = DictationStatsModel(modelContainer: try DictationStatsModel.makeInMemoryModelContainer())
            model.record(startedAt: Date(timeIntervalSince1970: 1), durationSeconds: 60, wordCount: 80)
            model.record(startedAt: Date(timeIntervalSince1970: 100), durationSeconds: 120, wordCount: 160)

            let summary = model.usageSummary()
            #expect(summary.sessionCount == 2)
            #expect(summary.totalDuration == 180)
            #expect(summary.wordCount == 240)
            #expect(summary.averageWordsPerMinute == 80)
            #expect(summary.timeSaved == 180)
        }

        @Test func formatsDurationWordCountAndSpeed() {
            let summary = DictationUsageSummary(
                sessionCount: 1,
                totalDuration: (13 * 3_600) + (20 * 60),
                wordCount: 103_000
            )

            #expect(summary.formattedDuration == "13 hr 20 min")
            #expect(summary.formattedWordCount == "103K")
            #expect(summary.formattedWordsPerMinute == "129")
            #expect(summary.formattedTimeSaved == "29 hr 35 min")
        }

        @Test func formatsEmptyAndCompactValues() {
            #expect(DictationUsageSummary.empty.formattedDuration == "0 sec")
            #expect(DictationUsageSummary.empty.formattedWordCount == "0")
            #expect(DictationUsageSummary.empty.formattedWordsPerMinute == "—")
            #expect(DictationUsageSummary.empty.formattedTimeSaved == "0 sec")

            let hoursOnly = DictationUsageSummary(sessionCount: 1, totalDuration: 51 * 3_600, wordCount: 0)
            #expect(hoursOnly.formattedDuration == "51 hr")

            let thousands = DictationUsageSummary(sessionCount: 1, totalDuration: 60, wordCount: 1_500)
            #expect(thousands.formattedWordCount == "1.5K")
        }

        @Test func activityContributionsMergeSessionsOnTheSameDay() throws {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            calendar.firstWeekday = 1

            let formatter = ISO8601DateFormatter()
            let morning = formatter.date(from: "2026-09-12T08:00:00Z")!
            let evening = formatter.date(from: "2026-09-12T18:00:00Z")!
            let now = formatter.date(from: "2026-09-12T20:00:00Z")!

            let model = DictationStatsModel(modelContainer: try DictationStatsModel.makeInMemoryModelContainer())
            model.record(startedAt: morning, durationSeconds: 60, wordCount: 100)
            model.record(startedAt: evening, durationSeconds: 30, wordCount: 50)

            let contributions = model.activityContributions(now: now, calendar: calendar)
            let day = calendar.startOfDay(for: morning)
            #expect(contributions[day] == 150)
            #expect(contributions.count == 1)
        }

        @Test func appUsageGroupsByBundleAndRanksByWords() throws {
            let model = DictationStatsModel(modelContainer: try DictationStatsModel.makeInMemoryModelContainer())
            model.record(
                startedAt: Date(), durationSeconds: 30, wordCount: 40,
                targetBundleID: "com.apple.Safari", targetAppName: "Safari")
            model.record(
                startedAt: Date(), durationSeconds: 20, wordCount: 10,
                targetBundleID: "com.apple.Safari", targetAppName: "Safari")
            model.record(
                startedAt: Date(), durationSeconds: 60, wordCount: 100,
                targetBundleID: "com.todesktop.230313mzl4w4u92", targetAppName: "Cursor")

            let apps = model.appUsage()
            #expect(apps.map(\.name) == ["Cursor", "Safari"])
            #expect(apps[0].sessionCount == 1)
            #expect(apps[0].wordCount == 100)
            #expect(apps[1].sessionCount == 2)
            #expect(apps[1].wordCount == 50)
            #expect(apps[0].share == 100.0 / 150.0)
        }

        @Test func appUsageOmitsUnknownAndBucketsOther() throws {
            let model = DictationStatsModel(modelContainer: try DictationStatsModel.makeInMemoryModelContainer())
            model.record(startedAt: Date(), durationSeconds: 10, wordCount: 10)
            model.record(startedAt: Date(), durationSeconds: 10, wordCount: 9, targetBundleID: "a", targetAppName: "A")
            model.record(startedAt: Date(), durationSeconds: 10, wordCount: 8, targetBundleID: "b", targetAppName: "B")
            model.record(startedAt: Date(), durationSeconds: 10, wordCount: 7, targetBundleID: "c", targetAppName: "C")
            model.record(startedAt: Date(), durationSeconds: 10, wordCount: 1, targetBundleID: "d", targetAppName: "D")

            let apps = model.appUsage(limit: 3)
            #expect(apps.map(\.name) == ["A", "B", "C", "Other"])
            #expect(apps[0].share == 9.0 / 25.0)
            #expect(apps[3].name == "Other")
            #expect(apps[3].sessionCount == 1)
            #expect(apps[3].wordCount == 1)
        }

        @Test func appUsageHidesListWhenEverySessionIsUnknown() throws {
            let model = DictationStatsModel(modelContainer: try DictationStatsModel.makeInMemoryModelContainer())
            model.record(startedAt: Date(), durationSeconds: 10, wordCount: 10)

            #expect(model.appUsage().isEmpty)
        }
    }
#endif
