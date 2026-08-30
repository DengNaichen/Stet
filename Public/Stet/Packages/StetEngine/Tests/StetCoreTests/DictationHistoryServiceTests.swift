import Foundation
import SwiftData
import Testing

@testable import StetCore

@MainActor
@Suite("Dictation history service", .serialized)
struct DictationHistoryServiceTests {
    @Test func existingEntryUsesActiveCompletedMigrationDefaults() {
        let entry = HistoryEntry(rawText: "existing")

        #expect(entry.captureMode == .active)
        #expect(entry.processingState == .completed)
        #expect(entry.captureStartedAt == entry.timestamp)
        #expect(entry.captureEndedAt == nil)
        #expect(entry.speakerRegions.isEmpty)
    }

    @Test func passiveCapturePersistsOrderedRegionsAndExportOmitsBiometricTemplates() throws {
        let service = try makeService()
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

        #expect(try service.createPassiveCapture(id: id, startedAt: startedAt) == id)
        try service.finishPassiveCapture(
            id: id,
            endedAt: startedAt.addingTimeInterval(1.6),
            rawText: "你好 你好",
            speakerRegions: regions
        )

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

    @Test func passiveCreationIsIdempotent() throws {
        let service = try makeService()
        let id = UUID()
        let startedAt = Date(timeIntervalSince1970: 2_000)

        #expect(try service.createPassiveCapture(id: id, startedAt: startedAt) == id)
        #expect(try service.createPassiveCapture(id: id, startedAt: startedAt) == id)
        #expect(try service.fetchRecent().map(\.id) == [id])
    }

    @Test func passiveUpdatesPersistIncrementalUnrewrittenTurns() throws {
        let service = try makeService()
        let id = UUID()
        let startedAt = Date(timeIntervalSince1970: 2_100)
        let first = region(start: 0, end: 600, speaker: .other, text: "呃，我们先看这个。")
        let second = region(start: 600, end: 1_200, speaker: .self, text: "好，继续。")
        _ = try service.createPassiveCapture(id: id, startedAt: startedAt)

        try service.updatePassiveCapture(
            id: id,
            rawText: "呃，我们先看这个。",
            speakerRegions: [first]
        )
        var entry = try #require(service.fetchRecent().first)
        #expect(entry.rawText == "呃，我们先看这个。")
        #expect(entry.speakerRegions == [first])
        #expect(entry.processingState == .processing)

        try service.updatePassiveCapture(
            id: id,
            rawText: "呃，我们先看这个。 好，继续。",
            speakerRegions: [first, second]
        )
        entry = try #require(service.fetchRecent().first)
        #expect(entry.rawText == "呃，我们先看这个。 好，继续。")
        #expect(entry.speakerRegions == [first, second])
        #expect(entry.llmText == nil)
        #expect(entry.finalText == nil)
    }

    @Test func passiveFailureRetainsCompletedTurns() throws {
        let service = try makeService()
        let id = UUID()
        let startedAt = Date(timeIntervalSince1970: 2_200)
        let completed = region(start: 0, end: 700, speaker: .self, text: "已经完成的内容")
        _ = try service.createPassiveCapture(id: id, startedAt: startedAt)
        try service.updatePassiveCapture(
            id: id,
            rawText: completed.text,
            speakerRegions: [completed]
        )

        try service.failPassiveCapture(
            id: id,
            endedAt: startedAt.addingTimeInterval(1),
            failureCode: "nano_failed",
            retainedText: completed.text,
            speakerRegions: [completed]
        )

        let entry = try #require(service.fetchRecent().first)
        #expect(entry.processingState == .failed)
        #expect(entry.processingFailureCode == "nano_failed")
        #expect(entry.rawText == completed.text)
        #expect(entry.speakerRegions == [completed])
    }

    @Test func passiveCompletionSurvivesTemporaryAudioCleanup() throws {
        let service = try makeService()
        let id = UUID()
        let startedAt = Date(timeIntervalSince1970: 2_300)
        let completed = region(start: 0, end: 500, speaker: .self, text: "只保留文字")
        let temporaryAudio = FileManager.default.temporaryDirectory
            .appendingPathComponent("stet-passive-history-\(UUID().uuidString).wav")
        try Data("temporary audio".utf8).write(to: temporaryAudio)
        defer { try? FileManager.default.removeItem(at: temporaryAudio) }
        _ = try service.createPassiveCapture(id: id, startedAt: startedAt)

        try service.finishPassiveCapture(
            id: id,
            endedAt: startedAt.addingTimeInterval(0.5),
            rawText: completed.text,
            speakerRegions: [completed]
        )
        try FileManager.default.removeItem(at: temporaryAudio)

        let entry = try #require(service.fetchRecent().first)
        #expect(entry.processingState == .completed)
        #expect(entry.rawText == "只保留文字")
        #expect(entry.speakerRegions == [completed])
        #expect(!FileManager.default.fileExists(atPath: temporaryAudio.path))
    }

    @Test func passiveMutationRejectsUnknownEntry() throws {
        let service = try makeService()
        let id = UUID()

        #expect(throws: PassiveHistoryError.entryNotFound) {
            try service.updatePassiveCapture(id: id, rawText: "", speakerRegions: [])
        }
        #expect(throws: PassiveHistoryError.entryNotFound) {
            try service.finishPassiveCapture(
                id: id,
                endedAt: Date(),
                rawText: "",
                speakerRegions: []
            )
        }
        #expect(throws: PassiveHistoryError.entryNotFound) {
            try service.failPassiveCapture(
                id: id,
                endedAt: Date(),
                failureCode: "nano_failed",
                retainedText: "",
                speakerRegions: []
            )
        }
    }

    @Test func passiveMutationValidatesRegionOrderAndOverlapIdentity() throws {
        let service = try makeService()
        let id = UUID()
        let startedAt = Date(timeIntervalSince1970: 3_000)
        _ = try service.createPassiveCapture(id: id, startedAt: startedAt)

        let reversed = [
            region(start: 900, end: 1_000, speaker: .other),
            region(start: 100, end: 200, speaker: .self),
        ]
        #expect(throws: PassiveHistoryError.invalidRegionOrder) {
            try service.updatePassiveCapture(id: id, rawText: "", speakerRegions: reversed)
        }

        let invalidOverlap = [
            region(start: 0, end: 500, speaker: .self, isOverlap: true)
        ]
        #expect(throws: PassiveHistoryError.invalidOverlapIdentity) {
            try service.updatePassiveCapture(id: id, rawText: "", speakerRegions: invalidOverlap)
        }

        let outside = [region(start: 0, end: 1_001, speaker: .other)]
        #expect(throws: PassiveHistoryError.regionOutsideCapture) {
            try service.finishPassiveCapture(
                id: id,
                endedAt: startedAt.addingTimeInterval(1),
                rawText: "",
                speakerRegions: outside
            )
        }
    }

    private func makeService() throws -> DictationHistoryService {
        let schema = Schema([HistoryEntry.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return DictationHistoryService(container: container)
    }

    private func region(
        start: Int,
        end: Int,
        speaker: CapturedSpeakerIdentity,
        text: String = "",
        isOverlap: Bool = false
    ) -> CapturedSpeakerRegion {
        CapturedSpeakerRegion(
            id: UUID(),
            startMilliseconds: start,
            endMilliseconds: end,
            speaker: speaker,
            text: text,
            identitySimilarity: nil,
            activityConfidence: nil,
            isOverlap: isOverlap
        )
    }
}
