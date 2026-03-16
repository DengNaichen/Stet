import Foundation
import Testing

@testable import Stet

@MainActor
@Suite("Transcription History Store", .serialized)
struct TranscriptionHistoryStoreTests {
    @Test func fileHistoryStoreRoundTripsRecords() async {
        let fileURL = TestSupport.temporaryFileURL(ext: "json")
        let store = FileTranscriptionHistoryStore(fileURL: fileURL)
        let records = [
            TranscriptionRecord(text: "hello", createdAt: Date(timeIntervalSince1970: 1_000_000)),
            TranscriptionRecord(
                text: "world",
                createdAt: Date(timeIntervalSince1970: 1_000_001),
                metadata: .init(kind: .rewrite)
            ),
        ]

        await store.saveHistory(records)
        let loaded = await store.loadHistory()

        #expect(loaded == records)
        try? FileManager.default.removeItem(at: fileURL)
    }

    @Test func fileHistoryStoreReturnsEmptyOnCorruptData() async throws {
        let fileURL = TestSupport.temporaryFileURL(ext: "json")
        try Data("bad json".utf8).write(to: fileURL)

        let store = FileTranscriptionHistoryStore(fileURL: fileURL)
        let loaded = await store.loadHistory()

        #expect(loaded.isEmpty)
        try? FileManager.default.removeItem(at: fileURL)
    }

    @Test func defaultFileURLPointsIntoApplicationSupport() {
        let url = FileTranscriptionHistoryStore.defaultFileURL()
        #expect(url.lastPathComponent == "transcription-history.json")
        #expect(url.path.contains("Application Support") || url.path.contains("/tmp/"))
    }
}
