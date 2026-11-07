import Foundation
import SwiftData
import Testing

@testable import StetCore

@MainActor
@Suite("Dictation history service", .serialized)
struct DictationHistoryServiceTests {
    @Test func finalDeliverySurvivesDelayedInsertion() async throws {
        let schema = Schema([HistoryEntry.self])
        let container = try ModelContainer(
            for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let service = DictationHistoryService(container: container) { isUpdate in
            if !isUpdate { try? await Task.sleep(for: .milliseconds(300)) }
        }
        service.recordRaw("original")
        let id = try #require(service.commitPending())
        service.updateFinal("delivered", targetBundleID: "com.example.editor", targetAppName: "Editor")
        await service.waitForWrites()
        let entry = try #require(service.fetchRecent().first { $0.id == id })
        #expect(entry.finalText == "delivered")
        #expect(entry.targetBundleID == "com.example.editor")
        #expect(entry.targetAppName == "Editor")
        #expect(entry.status == .completed)
    }

    @Test func lateNoHotwordTranscriptSurvivesInsertionBeyondFormerRetryWindow() async throws {
        let schema = Schema([HistoryEntry.self])
        let container = try ModelContainer(
            for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let service = DictationHistoryService(container: container) { isUpdate in
            if !isUpdate { try? await Task.sleep(for: .milliseconds(1200)) }
        }
        service.recordRaw("with hotwords")
        let id = try #require(service.commitPending())
        service.updateFinal("delivered", targetBundleID: nil, targetAppName: nil)
        service.recordRawWithoutHotwords("without hotwords")
        await service.waitForWrites()
        let entry = try #require(service.fetchRecent().first { $0.id == id })
        #expect(entry.rawTextWithoutHotwords == "without hotwords")
        #expect(entry.finalText == "delivered")
        #expect(entry.status == .completed)
    }

    @Test func consecutiveSessionsKeepTheirOwnDeliveryAndNoHotwordText() async throws {
        let service = try makeService()
        service.recordRaw("first raw")
        let firstID = try #require(service.commitPending())
        service.updateFinal("first final", targetBundleID: "first.app", targetAppName: "First")
        service.recordRawWithoutHotwords("first without")
        service.recordRaw("second raw")
        let secondID = try #require(service.commitPending())
        service.recordRawWithoutHotwords("second without")
        service.updateFinal(
            "second final", targetBundleID: "second.app", targetAppName: "Second",
            status: .clipboardPending)
        await service.waitForWrites()
        let entries = try service.fetchRecent()
        let first = try #require(entries.first { $0.id == firstID })
        let second = try #require(entries.first { $0.id == secondID })
        #expect(first.finalText == "first final")
        #expect(first.targetBundleID == "first.app")
        #expect(first.targetAppName == "First")
        #expect(first.rawTextWithoutHotwords == "first without")
        #expect(first.status == .completed)
        #expect(second.finalText == "second final")
        #expect(second.targetBundleID == "second.app")
        #expect(second.targetAppName == "Second")
        #expect(second.rawTextWithoutHotwords == "second without")
        #expect(second.status == .clipboardPending)
    }

    @Test func persistentHistorySurvivesAnotherSchemaOpeningLegacyStore() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try DictationHistoryService.makePersistentContainer(
            appSupportDirectory: directory, bundleIdentifier: "test")
        let service = DictationHistoryService(container: container)
        let id = UUID()
        let context = ModelContext(container)
        context.insert(HistoryEntry(id: id, rawText: "existing"))
        try context.save()
        let otherSchema = Schema([HistoryCollisionRecord.self])
        let other = try ModelContainer(
            for: otherSchema,
            configurations: [
                ModelConfiguration(
                    schema: otherSchema, url: directory.appendingPathComponent("default.store"))
            ])
        _ = try ModelContext(other).fetch(FetchDescriptor<HistoryCollisionRecord>())
        #expect(try service.fetchRecent().map(\.id) == [id])
    }

    @Test func legacyHistoryIsCopiedWithAllTextStagesAndOriginalRetained() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = Schema([HistoryEntry.self])
        let legacy = try ModelContainer(
            for: schema,
            configurations: [
                ModelConfiguration(
                    schema: schema, url: directory.appendingPathComponent("default.store"))
            ])
        let context = ModelContext(legacy)
        let original = HistoryEntry(rawText: "raw", llmText: "refined", finalText: "delivered")
        context.insert(original)
        try context.save()
        let container = try DictationHistoryService.makePersistentContainer(
            appSupportDirectory: directory, bundleIdentifier: "test")
        let service = DictationHistoryService(container: container)
        let entry = try #require(service.fetchRecent().first)
        #expect(entry.id == original.id)
        #expect(entry.rawText == "raw")
        #expect(entry.llmText == "refined")
        #expect(entry.finalText == "delivered")
        #expect(try ModelContext(legacy).fetchCount(FetchDescriptor<HistoryEntry>()) == 1)
        try service.deleteAll()
        let reopened = try DictationHistoryService.makePersistentContainer(
            appSupportDirectory: directory, bundleIdentifier: "test")
        #expect(try DictationHistoryService(container: reopened).fetchRecent().isEmpty)
    }

    @Test func unavailableHistoryThrowsInsteadOfPretendingToBeEmpty() {
        #expect(throws: (any Error).self) { try DictationHistoryService(container: nil).fetchRecent() }
    }

    @Test func existingEntryUsesActiveCompletedMigrationDefaults() {
        let entry = HistoryEntry(rawText: "existing")

        #expect(entry.captureMode == .active)
        #expect(entry.processingState == .completed)
        #expect(entry.captureStartedAt == entry.timestamp)
        #expect(entry.captureEndedAt == nil)
        #expect(entry.speakerRegions.isEmpty)
        #expect(entry.rawTextWithoutHotwords == nil)
    }

    @Test func legacyPassiveHistoryRemainsReadableAndExportable() throws {
        let container = try ModelContainer(
            for: HistoryEntry.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let service = DictationHistoryService(container: container)
        let id = UUID()
        let startedAt = Date(timeIntervalSince1970: 1_000)
        let regions = [
            CapturedSpeakerRegion(
                id: UUID(),
                startMilliseconds: 0,
                endMilliseconds: 800,
                speaker: .other,
                text: "你好",
                identitySimilarity: 0.31,
                activityConfidence: 0.92,
                isOverlap: false
            ),
            CapturedSpeakerRegion(
                id: UUID(),
                startMilliseconds: 800,
                endMilliseconds: 1_600,
                speaker: .self,
                text: "你好",
                identitySimilarity: 0.79,
                activityConfidence: 0.96,
                isOverlap: false
            ),
        ]

        let context = ModelContext(container)
        context.insert(
            HistoryEntry(
                id: id, rawText: "你好 你好", status: .notDelivered,
                captureMode: .passive, captureStartedAt: startedAt,
                captureEndedAt: startedAt.addingTimeInterval(1.6),
                processingState: .completed, speakerRegions: regions))
        try context.save()

        let entry = try #require(service.fetchRecent().first)
        #expect(entry.captureMode == .passive)
        #expect(entry.captureStartedAt == startedAt)
        #expect(entry.captureEndedAt == startedAt.addingTimeInterval(1.6))
        #expect(entry.processingState == .completed)
        #expect(entry.status == .notDelivered)
        #expect(entry.rawText == "你好 你好")
        #expect(entry.llmText == nil)
        #expect(entry.finalText == nil)
        #expect(entry.targetBundleID == nil)
        #expect(entry.targetAppName == nil)
        #expect(entry.speakerRegions == regions)

        let data = try JSONEncoder().encode(HistoryEntry.ExportRepresentation(from: entry))
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("speakerRegions"))
        #expect(!json.localizedCaseInsensitiveContains("centroid"))
        #expect(!json.localizedCaseInsensitiveContains("embedding"))
    }

    @Test func noHotwordTranscriptAttachesBeforeCommit() async throws {
        let service = try makeService()
        service.recordRaw("with hotwords")
        service.recordRawWithoutHotwords("without hotwords")
        let id = try #require(service.commitPending())

        let entry = try await waitForEntry(in: service, id: id)
        #expect(entry.rawText == "with hotwords")
        #expect(entry.rawTextWithoutHotwords == "without hotwords")
        #expect(entry.llmText == nil)
    }

    @Test func noHotwordTranscriptAttachesAfterCommitAndUpdateFinal() async throws {
        let service = try makeService()
        service.recordRaw("with hotwords")
        let id = try #require(service.commitPending())
        _ = try await waitForEntry(in: service, id: id)
        service.updateFinal(
            "delivered",
            targetBundleID: "com.example.editor",
            targetAppName: "Editor"
        )
        service.recordRawWithoutHotwords("without hotwords")

        let entry = try await waitForEntry(in: service, id: id) {
            $0.rawTextWithoutHotwords == "without hotwords"
        }
        #expect(entry.rawText == "with hotwords")
        #expect(entry.rawTextWithoutHotwords == "without hotwords")
        #expect(entry.finalText == "delivered")
    }

    @Test func nextRecordRawDoesNotReceivePreviousNoHotwordTranscript() async throws {
        let service = try makeService()
        service.recordRaw("first")
        let firstID = try #require(service.commitPending())
        _ = try await waitForEntry(in: service, id: firstID)
        service.updateFinal("first delivered", targetBundleID: nil, targetAppName: nil)
        service.recordRaw("second")
        service.recordRawWithoutHotwords("second without")
        let secondID = try #require(service.commitPending())

        let first = try await waitForEntry(in: service, id: firstID)
        let second = try await waitForEntry(in: service, id: secondID)
        #expect(first.rawTextWithoutHotwords == nil)
        #expect(second.rawTextWithoutHotwords == "second without")
    }

    private func waitForEntry(
        in service: DictationHistoryService,
        id: UUID,
        timeout: Duration = .seconds(2),
        matching: ((HistoryEntry) -> Bool)? = nil
    ) async throws -> HistoryEntry {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            if let entry = try service.fetchRecent().first(where: { $0.id == id }),
                matching?(entry) ?? true
            {
                return entry
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        let entry = try #require(service.fetchRecent().first(where: { $0.id == id }))
        if let matching {
            #expect(matching(entry))
        }
        return entry
    }

    private func makeService() throws -> DictationHistoryService {
        let schema = Schema([HistoryEntry.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return DictationHistoryService(container: container)
    }

}

@Model
private final class HistoryCollisionRecord {
    var name: String = ""
    init() {}
}
