import Foundation
import StetCore
import SwiftData
import Testing
@testable import StetMobile

@MainActor
struct HistoryViewModelTests {
    @Test
    func reloadFetchesEntriesAndComputesUsageStats() throws {
        let container = try StetCloudDataContainer.makeInMemoryContainer()
        let notificationCenter = NotificationCenter()
        let now = Date()
        let earlier = now.addingTimeInterval(-300)

        let context = ModelContext(container)
        context.insert(
            HistoryEntry(
                timestamp: earlier,
                rawText: "raw draft from iphone",
                llmText: nil,
                finalText: "raw draft from iphone",
                targetBundleID: "NaichengDeng.StetMobile",
                targetAppName: "Stet iOS",
                status: .completed
            )
        )
        context.insert(
            HistoryEntry(
                timestamp: now,
                rawText: "uh deploy stet sync",
                llmText: "Deploy Stet sync.",
                finalText: "Deploy Stet sync.",
                targetBundleID: "com.tinyspeck.slackmacgap",
                targetAppName: "Slack",
                status: .completed
            )
        )
        try context.save()

        let statsModel = DictationStatsModel(modelContainer: container)
        statsModel.record(
            startedAt: earlier,
            durationSeconds: 4,
            wordCount: 40,
            targetBundleID: "NaichengDeng.StetMobile",
            targetAppName: "Stet iOS",
            sourcePlatform: "iOS"
        )
        statsModel.record(
            startedAt: now,
            durationSeconds: 6,
            wordCount: 60,
            targetBundleID: "com.tinyspeck.slackmacgap",
            targetAppName: "Slack",
            sourcePlatform: "macOS"
        )

        let viewModel = HistoryViewModel(
            modelContainer: container,
            notificationCenter: notificationCenter
        )
        viewModel.reload()

        #expect(viewModel.loadError == nil)
        #expect(viewModel.entries.count == 2)
        #expect(viewModel.entries[0].displayText == "Deploy Stet sync.")
        #expect(viewModel.entries[0].appDisplayName == "Slack")
        #expect(viewModel.entries[0].isRewritten)
        #expect(viewModel.entries[0].hasDistinctRawText)

        #expect(viewModel.entries[1].displayText == "raw draft from iphone")
        #expect(viewModel.entries[1].appDisplayName == "Stet iOS")
        #expect(!viewModel.entries[1].isRewritten)
        #expect(!viewModel.entries[1].hasDistinctRawText)

        #expect(viewModel.usageSummary.sessionCount == 2)
        #expect(viewModel.usageSummary.wordCount == 100)
        #expect(viewModel.usageSummary.totalDuration == 10)
        #expect(viewModel.usageSummary.timeSaved > 0)

        let today = Calendar.current.startOfDay(for: now)
        #expect(viewModel.activityDetails[today]?.wordCount == 100)
    }

    @Test
    func searchFiltersByTranscriptAndAppMetadata() throws {
        let container = try StetCloudDataContainer.makeInMemoryContainer()
        let context = ModelContext(container)
        context.insert(
            HistoryEntry(
                timestamp: Date(),
                rawText: "fix cloudkit entitlement",
                llmText: "Fix CloudKit entitlement.",
                finalText: "Fix CloudKit entitlement.",
                targetBundleID: "com.apple.dt.Xcode",
                targetAppName: "Xcode",
                status: .completed
            )
        )
        context.insert(
            HistoryEntry(
                timestamp: Date().addingTimeInterval(-60),
                rawText: "buy coffee beans",
                llmText: nil,
                finalText: "Buy coffee beans",
                targetBundleID: "com.apple.mobilenotes",
                targetAppName: "Notes",
                status: .completed
            )
        )
        try context.save()

        let viewModel = HistoryViewModel(modelContainer: container, notificationCenter: NotificationCenter())
        viewModel.reload()

        viewModel.searchText = "xcode"
        #expect(viewModel.filteredEntries.count == 1)
        #expect(viewModel.filteredEntries[0].appDisplayName == "Xcode")

        viewModel.searchText = "  coffee  "
        #expect(viewModel.filteredEntries.count == 1)
        #expect(viewModel.filteredEntries[0].appDisplayName == "Notes")

        viewModel.searchText = "nonexistent-query"
        #expect(viewModel.filteredEntries.isEmpty)

        viewModel.searchText = ""
        #expect(viewModel.filteredEntries.count == 2)
    }

    @Test
    func remoteCloudChangeNotificationReloadsEntriesAndStats() throws {
        let container = try StetCloudDataContainer.makeInMemoryContainer()
        let notificationCenter = NotificationCenter()
        let viewModel = HistoryViewModel(
            modelContainer: container,
            notificationCenter: notificationCenter
        )
        viewModel.reload()
        #expect(viewModel.entries.isEmpty)
        #expect(viewModel.usageSummary == .empty)

        let context = ModelContext(container)
        context.insert(
            HistoryEntry(
                timestamp: Date(),
                rawText: "synced from mac",
                llmText: "Synced from Mac.",
                finalText: "Synced from Mac.",
                targetBundleID: "com.apple.dt.Xcode",
                targetAppName: "Xcode",
                status: .completed
            )
        )
        try context.save()

        DictationStatsModel(modelContainer: container).record(
            startedAt: Date(),
            durationSeconds: 3,
            wordCount: 3,
            targetBundleID: "com.apple.dt.Xcode",
            targetAppName: "Xcode",
            sourcePlatform: "macOS"
        )

        notificationCenter.post(name: .stetCloudDataDidChange, object: nil)

        #expect(viewModel.entries.count == 1)
        #expect(viewModel.entries[0].displayText == "Synced from Mac.")
        #expect(viewModel.usageSummary.sessionCount == 1)
        #expect(viewModel.usageSummary.wordCount == 3)
    }

    @Test
    func deleteAllRemovesPersistedHistoryEntries() throws {
        let container = try StetCloudDataContainer.makeInMemoryContainer()
        let context = ModelContext(container)
        context.insert(
            HistoryEntry(
                timestamp: Date(),
                rawText: "temporary entry",
                finalText: "temporary entry",
                targetAppName: "Stet iOS",
                status: .completed
            )
        )
        try context.save()

        let viewModel = HistoryViewModel(modelContainer: container, notificationCenter: NotificationCenter())
        viewModel.reload()
        #expect(viewModel.entries.count == 1)

        viewModel.deleteAll()
        #expect(viewModel.entries.isEmpty)

        viewModel.reload()
        #expect(viewModel.entries.isEmpty)
    }
}
