import Foundation
import SwiftData

// MARK: - DictationHistoryService

/// Manages the persistent history of dictation sessions.
///
/// All mutation methods are `@MainActor` to match the dictation pipeline's actor context.
/// Persistence writes are dispatched to a background `ModelContext` so they never
/// block the main thread or the audio/transcription pipeline.
@MainActor
public final class DictationHistoryService {
    public static let shared = DictationHistoryService()

    // MARK: - Internal session accumulator

    /// Ephemeral value type that accumulates data across the three pipeline stages.
    /// Discarded without saving if the session is abandoned (cancelled / empty text).
    private struct PendingSession {
        var rawText: String
        var llmText: String?
        var finalText: String?
        var targetBundleID: String?
        var targetAppName: String?
        let timestamp: Date

        init(rawText: String) {
            self.rawText = rawText
            self.timestamp = Date()
        }
    }

    // MARK: - Private state

    private let container: ModelContainer?
    private var pending: PendingSession?

    // MARK: - Init

    private init() {
        do {
            let schema = Schema([HistoryEntry.self])
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            self.container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            self.container = nil
        }
    }

    // MARK: - Pipeline recording API

    /// Called when raw ASR text is available. Opens a new pending session.
    /// If a previous session was still pending it is silently discarded.
    public func recordRaw(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            pending = nil
            return
        }
        pending = PendingSession(rawText: trimmed)
    }

    /// Called after the LLM transformer runs. Updates the pending session.
    public func recordLLM(_ text: String) {
        pending?.llmText = text
    }

    /// Called when the text has been successfully delivered to the target app.
    /// Persists the entry and clears the pending session.
    public func recordFinal(
        _ text: String,
        targetBundleID: String?,
        targetAppName: String?,
        status: HistoryEntryStatus = .completed
    ) {
        guard var session = pending else { return }
        pending = nil

        session.finalText = text
        session.targetBundleID = targetBundleID
        session.targetAppName = targetAppName

        persistEntry(from: session, status: status)
    }

    /// Discards the current pending session without saving.
    /// Call this when a capture is cancelled or results in an empty transcription.
    public func discardPendingSession() {
        pending = nil
    }

    // MARK: - Query API

    /// Fetches history entries sorted by recency, up to `limit` results.
    public func fetchRecent(limit: Int = 300) throws -> [HistoryEntry] {
        guard let container else { return [] }
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<HistoryEntry>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor)
    }

    /// Permanently deletes all history entries.
    public func deleteAll() throws {
        guard let container else { return }
        let context = ModelContext(container)
        try context.delete(model: HistoryEntry.self)
        try context.save()
    }

    // MARK: - Private helpers

    private func persistEntry(from session: PendingSession, status: HistoryEntryStatus) {
        guard let container else { return }

        // Capture plain value data so it can safely cross actor boundaries.
        let rawText = session.rawText
        let llmText = session.llmText
        let finalText = session.finalText
        let targetBundleID = session.targetBundleID
        let targetAppName = session.targetAppName
        let timestamp = session.timestamp

        Task.detached(priority: .background) {
            let context = ModelContext(container)
            let entry = HistoryEntry(
                timestamp: timestamp,
                rawText: rawText,
                llmText: llmText,
                finalText: finalText,
                targetBundleID: targetBundleID,
                targetAppName: targetAppName,
                status: status
            )
            context.insert(entry)
            try? context.save()
        }
    }
}
