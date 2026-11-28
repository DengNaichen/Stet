import Foundation
import SwiftData
import OSLog

@MainActor
public protocol DictationHistoryRecording: AnyObject {
    func recordRaw(_ text: String)
    func recordLLM(_ text: String)
    func recordRawWithoutHotwords(_ text: String)
    @discardableResult
    func commitPending() -> UUID?
}

// MARK: - DictationHistoryService

/// Manages the persistent history of dictation sessions.
///
/// All mutation methods are `@MainActor` to match the dictation pipeline's actor context.
/// Persistence writes are dispatched to a background `ModelContext` so they never
/// block the main thread or the audio/transcription pipeline.
@MainActor
public final class DictationHistoryService: DictationHistoryRecording {
    public static let shared = DictationHistoryService()

    // MARK: - Internal session accumulator

    /// Ephemeral value type that accumulates data across the three pipeline stages.
    private struct PendingSession {
        var rawText: String
        var rawTextWithoutHotwords: String?
        var llmText: String?
        var finalText: String?
        var targetBundleID: String?
        var targetAppName: String?
        let timestamp: Date
        /// Set after the entry has been persisted via commitPending().
        var persistedEntryID: UUID?

        init(rawText: String) {
            self.rawText = rawText
            self.timestamp = Date()
        }
    }

    // MARK: - Private state

    private let container: ModelContainer?
    private var lastWrite: Task<Void, Never>?
    private nonisolated static let logger = Logger(subsystem: "StetCore", category: "DictationHistory")
    // Internal scheduling seam for persistence regression tests.
    private var beforeWrite: @Sendable (Bool) async -> Void = { _ in }

    func waitForWrites() async {
        await lastWrite?.value
    }

    private var initializationError: Error?
    private var pending: PendingSession?
    private var lastCommittedEntryID: UUID?
    private var stagedRawTextWithoutHotwords: String?

    // MARK: - Init

    private init() {
        self.container = StetCloudDataContainer.shared.modelContainer
        self.initializationError = StetCloudDataContainer.shared.initializationError
    }

    static func makePersistentContainer(
        appSupportDirectory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0],
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "NaichengDeng.Stet"
    ) throws -> ModelContainer {
        try StetCloudDataContainer.makePersistentContainer(
            appSupportDirectory: appSupportDirectory, bundleIdentifier: bundleIdentifier)
    }

    init(container: ModelContainer?, beforeWrite: @escaping @Sendable (Bool) async -> Void = { _ in }) {
        self.container = container
        self.beforeWrite = beforeWrite
    }

    // MARK: - Pipeline recording API

    /// Persists a finished session without disturbing the live pipeline's pending session.
    @discardableResult
    public func recordCompleted(
        rawText: String, llmText: String? = nil, finalText: String? = nil,
        targetBundleID: String? = nil, targetAppName: String? = nil, timestamp: Date = Date(),
        status: HistoryEntryStatus = .completed
    ) -> UUID? {
        let raw = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, let container else { return nil }
        let id = UUID()
        enqueueWrite(isUpdate: false) {
            let context = ModelContext(container)
            context.insert(
                HistoryEntry(
                    id: id, timestamp: timestamp, rawText: raw, llmText: llmText, finalText: finalText,
                    targetBundleID: targetBundleID, targetAppName: targetAppName, status: status))
            try context.save()
        }
        return id
    }

    /// Called when raw ASR text is available. Opens a new pending session.
    /// If a previous session was still pending it is silently discarded.
    public func recordRaw(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            pending = nil
            return
        }
        pending = PendingSession(rawText: trimmed)
        lastCommittedEntryID = nil
        if let staged = stagedRawTextWithoutHotwords {
            pending?.rawTextWithoutHotwords = staged
            stagedRawTextWithoutHotwords = nil
        }
    }

    /// Called after the LLM transformer runs. Updates the pending session.
    public func recordLLM(_ text: String) {
        pending?.llmText = text
    }

    public func recordRawWithoutHotwords(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if var session = pending {
            session.rawTextWithoutHotwords = trimmed
            pending = session
            if let id = session.persistedEntryID {
                updateRawTextWithoutHotwords(id: id, text: trimmed)
            }
            return
        }
        if let id = lastCommittedEntryID {
            updateRawTextWithoutHotwords(id: id, text: trimmed)
            return
        }
        stagedRawTextWithoutHotwords = trimmed
    }

    /// Drops a no-hotword transcript that arrived before `recordRaw` for this utterance.
    public func discardUncommittedNoHotwordTranscript() {
        stagedRawTextWithoutHotwords = nil
    }

    /// Immediately persists the pending session with `.processing` status.
    /// Call this as soon as transcription + optional LLM refinement are complete,
    /// before waiting for any delivery confirmation.
    /// - Returns: The persisted entry's UUID, or nil if there was nothing to save.
    @discardableResult
    public func commitPending() -> UUID? {
        guard var session = pending else { return nil }
        let id = UUID()
        session.persistedEntryID = id
        lastCommittedEntryID = id
        pending = session
        persistEntry(from: session, id: id, status: .processing)
        return id
    }

    /// Updates the already-persisted entry with the final delivered text and status.
    /// Safe to call even if `commitPending()` was never called (no-op in that case).
    public func updateFinal(
        _ text: String,
        targetBundleID: String?,
        targetAppName: String?,
        status: HistoryEntryStatus = .completed
    ) {
        guard let id = pending?.persistedEntryID else { return }
        pending = nil
        updateEntry(
            id: id, finalText: text, targetBundleID: targetBundleID, targetAppName: targetAppName, status: status)
    }

    /// Discards the current pending session without saving.
    /// Call this when a capture is cancelled or results in an empty transcription.
    public func discardPendingSession() {
        pending = nil
        lastCommittedEntryID = nil
        stagedRawTextWithoutHotwords = nil
    }

    // MARK: - Query API

    /// Fetches history entries sorted by recency, up to `limit` results.
    public func fetchRecent(limit: Int = 300) throws -> [HistoryEntry] {
        let context = try persistenceContext()
        var descriptor = FetchDescriptor<HistoryEntry>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor)
    }

    /// Permanently deletes all history entries.
    public func deleteAll() throws {
        let context = try persistenceContext()
        try context.delete(model: HistoryEntry.self)
        try context.save()
    }

    // MARK: - Private helpers

    private func persistEntry(from session: PendingSession, id: UUID, status: HistoryEntryStatus) {
        guard let container else { return }

        let rawText = session.rawText
        let rawTextWithoutHotwords = session.rawTextWithoutHotwords
        let llmText = session.llmText
        let timestamp = session.timestamp

        enqueueWrite(isUpdate: false) {
            let context = ModelContext(container)
            let entry = HistoryEntry(
                id: id,
                timestamp: timestamp,
                rawText: rawText,
                rawTextWithoutHotwords: rawTextWithoutHotwords,
                llmText: llmText,
                status: status
            )
            context.insert(entry)
            try context.save()
        }
    }

    private func updateRawTextWithoutHotwords(id: UUID, text: String) {
        guard let container else { return }

        enqueueWrite(isUpdate: true) {
            let context = ModelContext(container)
            var descriptor = FetchDescriptor<HistoryEntry>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            guard let entry = try context.fetch(descriptor).first else {
                throw HistoryPersistenceError.entryNotFound
            }
            entry.rawTextWithoutHotwords = text
            try context.save()
        }
    }

    private func updateEntry(
        id: UUID,
        finalText: String,
        targetBundleID: String?,
        targetAppName: String?,
        status: HistoryEntryStatus
    ) {
        guard let container else { return }

        enqueueWrite(isUpdate: true) {
            let context = ModelContext(container)
            var descriptor = FetchDescriptor<HistoryEntry>(
                predicate: #Predicate { $0.id == id }
            )
            descriptor.fetchLimit = 1
            guard let entry = try context.fetch(descriptor).first else {
                throw HistoryPersistenceError.entryNotFound
            }
            entry.finalText = finalText
            entry.targetBundleID = targetBundleID
            entry.targetAppName = targetAppName
            entry.status = status
            try context.save()
        }
    }

    /// MainActor establishes submission order; each background write waits for its predecessor.
    /// The operation is synchronous so a ModelContext never crosses a suspension point.
    private func enqueueWrite(isUpdate: Bool, operation: @escaping @Sendable () throws -> Void) {
        let predecessor = lastWrite
        lastWrite = Task.detached(priority: .background) { [beforeWrite] in
            await predecessor?.value
            await beforeWrite(isUpdate)
            do {
                try operation()
            } catch {
                Self.logger.error("History write failed: \(String(describing: error), privacy: .private)")
            }
        }
    }

    private func persistenceContext() throws -> ModelContext {
        guard let container else {
            throw initializationError ?? HistoryPersistenceError.unavailable
        }
        return ModelContext(container)
    }

}

private enum HistoryPersistenceError: Error {
    case unavailable
    case entryNotFound
}
