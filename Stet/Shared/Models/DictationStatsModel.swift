#if os(macOS)
    import Foundation
    import SwiftData

    nonisolated private let sharedDictationStatsModelContainer: ModelContainer? = {
        do {
            return try DictationStatsModel.makePersistentModelContainer()
        } catch {
            AppLogger.error("Failed to create DictationStatsModel container. error=\(error)")
            return nil
        }
    }()

    @Model
    final class DictationSessionRecord {
        var startedAt: Date = Date()
        var durationSeconds: Double = 0
        var wordCount: Int = 0

        init(startedAt: Date, durationSeconds: Double, wordCount: Int) {
            self.startedAt = startedAt
            self.durationSeconds = durationSeconds
            self.wordCount = wordCount
        }
    }

    struct DictationStatsModel: @unchecked Sendable {
        static let shared = DictationStatsModel()

        nonisolated private let modelContainer: ModelContainer?

        nonisolated init(modelContainer: ModelContainer? = sharedDictationStatsModelContainer) {
            self.modelContainer = modelContainer
        }

        nonisolated func record(startedAt: Date, durationSeconds: Double, wordCount: Int) {
            guard let context = modelContext else { return }
            context.insert(
                DictationSessionRecord(startedAt: startedAt, durationSeconds: durationSeconds, wordCount: wordCount)
            )
            try? context.save()
        }

        nonisolated func todaySessionCount() -> Int {
            fetchSessions(since: startOfToday()).count
        }

        nonisolated func todayTotalDuration() -> TimeInterval {
            fetchSessions(since: startOfToday()).reduce(0) { $0 + $1.durationSeconds }
        }

        nonisolated func allTimeSessionCount() -> Int {
            fetchSessions(since: nil).count
        }

        nonisolated func allTimeTotalDuration() -> TimeInterval {
            fetchSessions(since: nil).reduce(0) { $0 + $1.durationSeconds }
        }

        nonisolated func todayTotalWordCount() -> Int {
            fetchSessions(since: startOfToday()).reduce(0) { $0 + $1.wordCount }
        }

        nonisolated func allTimeTotalWordCount() -> Int {
            fetchSessions(since: nil).reduce(0) { $0 + $1.wordCount }
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
