#if os(macOS)
    import Foundation
    import Testing

    @testable import Stet

    @Suite("Dictation Word Counter")
    struct DictationWordCounterTests {
        @Test func latinTokensMatchEverydayEnglish() {
            #expect(DictationWordCounter.displayUnits(in: "hello world") == 2)
            #expect(DictationWordCounter.displayUnits(in: "don't stop") == 2)
        }

        @Test func hanCharactersEachCountAsOneUnit() {
            #expect(DictationWordCounter.displayUnits(in: "我觉得可以") == 5)
        }

        @Test func mixedChineseAndEnglishCountsCharactersAndTokens() {
            #expect(DictationWordCounter.displayUnits(in: "用 Cursor 写代码") == 5)
        }
    }

    @Suite("Dictation Stats Recount")
    struct DictationStatsRecountTests {
        @Test func recountsMatchedSessionsFromHistoryText() throws {
            let model = DictationStatsModel(modelContainer: try DictationStatsModel.makeInMemoryModelContainer())
            let start = Date(timeIntervalSince1970: 1_000)
            model.record(startedAt: start, durationSeconds: 10, wordCount: 2)
            model.record(startedAt: start.addingTimeInterval(60), durationSeconds: 10, wordCount: 2)

            let result = model.recountDisplayUnits(
                from: [
                    .init(endedAt: start.addingTimeInterval(10), text: "我觉得可以"),
                    .init(endedAt: start.addingTimeInterval(200), text: "left unmatched"),
                ]
            )

            #expect(result == .init(updated: 1, unmatched: 1))
            #expect(model.usageSummary().wordCount == 7)
        }

        @Test func migrateIfNeededRunsOnce() throws {
            let defaults = TestSupport.makeUserDefaults()
            let model = DictationStatsModel(modelContainer: try DictationStatsModel.makeInMemoryModelContainer())
            let start = Date(timeIntervalSince1970: 2_000)
            model.record(startedAt: start, durationSeconds: 8, wordCount: 1)

            let first = model.recountDisplayUnits(
                from: [.init(endedAt: start.addingTimeInterval(8), text: "你好")]
            )
            #expect(first.updated == 1)
            defaults.set(DictationWordCountMigration.scheme, forKey: MacPreferences.dictationWordCountScheme)
            #expect(defaults.integer(forKey: MacPreferences.dictationWordCountScheme) == 2)
            #expect(model.usageSummary().wordCount == 2)
        }
    }
#endif
