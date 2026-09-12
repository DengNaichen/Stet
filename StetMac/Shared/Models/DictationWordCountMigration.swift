#if os(macOS)
    import Foundation
    import StetCore
    import os

    /// One-time recount of Overview stats using History transcripts.
    ///
    /// Sessions without a matching history row keep their tokenizer word count.
    /// A global 1.57× scale would inflate English users, so unmatched rows are
    /// left alone. New recordings use `DictationWordCounter` directly.
    enum DictationWordCountMigration {
        static let scheme = 2
        static let matchWindow: TimeInterval = 3

        private static let logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "com.openwhispr.Stet",
            category: "general"
        )

        @MainActor
        static func migrateIfNeeded(
            defaults: UserDefaults = .standard,
            history: DictationHistoryService = .shared,
            stats: DictationStatsModel = .shared
        ) {
            guard defaults.integer(forKey: MacPreferences.dictationWordCountScheme) < scheme else {
                return
            }

            let entries = (try? history.fetchRecent(limit: 10_000)) ?? []
            let texts: [DictationStatsModel.HistoryTranscript] = entries.compactMap { entry in
                let text = (entry.finalText ?? entry.llmText ?? entry.rawText)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }
                return .init(endedAt: entry.timestamp, text: text)
            }
            let result = stats.recountDisplayUnits(from: texts, matchWindow: matchWindow)
            defaults.set(scheme, forKey: MacPreferences.dictationWordCountScheme)
            logger.info(
                "Recounted dictation word units updated=\(result.updated) unmatched=\(result.unmatched)"
            )
        }
    }
#endif
