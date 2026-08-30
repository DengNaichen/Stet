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
    private struct PendingSession {
        var rawText: String
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

    init(container: ModelContainer?) {
        self.container = container
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

    /// Immediately persists the pending session with `.processing` status.
    /// Call this as soon as transcription + optional LLM refinement are complete,
    /// before waiting for any delivery confirmation.
    /// - Returns: The persisted entry's UUID, or nil if there was nothing to save.
    @discardableResult
    public func commitPending() -> UUID? {
        guard var session = pending else { return nil }
        let id = UUID()
        session.persistedEntryID = id
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

    // MARK: - Passive capture API

    @discardableResult
    public func createPassiveCapture(id: UUID, startedAt: Date) throws -> UUID {
        let context = try persistenceContext()
        if try entry(id: id, in: context) != nil {
            return id
        }

        context.insert(
            HistoryEntry(
                id: id,
                timestamp: startedAt,
                rawText: "",
                status: .notDelivered,
                captureMode: .passive,
                captureStartedAt: startedAt,
                processingState: .processing
            )
        )
        try save(context)
        return id
    }

    public func updatePassiveCapture(
        id: UUID,
        rawText: String,
        speakerRegions: [CapturedSpeakerRegion]
    ) throws {
        let context = try persistenceContext()
        let entry = try requiredEntry(id: id, in: context)
        try Self.validate(speakerRegions: speakerRegions, durationMilliseconds: nil)
        try entry.updatePassiveFields(
            endedAt: nil,
            processingState: .processing,
            failureCode: nil,
            rawText: rawText,
            speakerRegions: speakerRegions
        )
        try save(context)
    }

    public func finishPassiveCapture(
        id: UUID,
        endedAt: Date,
        rawText: String,
        speakerRegions: [CapturedSpeakerRegion]
    ) throws {
        try completePassiveCapture(
            id: id,
            endedAt: endedAt,
            rawText: rawText,
            speakerRegions: speakerRegions,
            state: .completed,
            failureCode: nil
        )
    }

    public func failPassiveCapture(
        id: UUID,
        endedAt: Date,
        failureCode: String,
        retainedText: String,
        speakerRegions: [CapturedSpeakerRegion]
    ) throws {
        try completePassiveCapture(
            id: id,
            endedAt: endedAt,
            rawText: retainedText,
            speakerRegions: speakerRegions,
            state: .failed,
            failureCode: failureCode
        )
    }

    // MARK: - Private helpers

    private func persistEntry(from session: PendingSession, id: UUID, status: HistoryEntryStatus) {
        guard let container else { return }

        let rawText = session.rawText
        let llmText = session.llmText
        let timestamp = session.timestamp

        Task.detached(priority: .background) {
            let context = ModelContext(container)
            let entry = HistoryEntry(
                id: id,
                timestamp: timestamp,
                rawText: rawText,
                llmText: llmText,
                status: status
            )
            context.insert(entry)
            try? context.save()
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

        Task.detached(priority: .background) {
            let context = ModelContext(container)
            var descriptor = FetchDescriptor<HistoryEntry>(
                predicate: #Predicate { $0.id == id }
            )
            descriptor.fetchLimit = 1
            guard let entry = try? context.fetch(descriptor).first else { return }
            entry.finalText = finalText
            entry.targetBundleID = targetBundleID
            entry.targetAppName = targetAppName
            entry.status = status
            try? context.save()
        }
    }

    private func completePassiveCapture(
        id: UUID,
        endedAt: Date,
        rawText: String,
        speakerRegions: [CapturedSpeakerRegion],
        state: TranscriptProcessingState,
        failureCode: String?
    ) throws {
        let context = try persistenceContext()
        let entry = try requiredEntry(id: id, in: context)
        guard endedAt >= entry.captureStartedAt else {
            throw PassiveHistoryError.invalidInterval
        }

        let durationMilliseconds = Int(
            (endedAt.timeIntervalSince(entry.captureStartedAt) * 1_000).rounded()
        )
        try Self.validate(
            speakerRegions: speakerRegions,
            durationMilliseconds: durationMilliseconds
        )
        try entry.updatePassiveFields(
            endedAt: endedAt,
            processingState: state,
            failureCode: failureCode,
            rawText: rawText,
            speakerRegions: speakerRegions
        )
        try save(context)
    }

    private func persistenceContext() throws -> ModelContext {
        guard let container else {
            throw PassiveHistoryError.persistenceUnavailable
        }
        return ModelContext(container)
    }

    private func requiredEntry(id: UUID, in context: ModelContext) throws -> HistoryEntry {
        guard let entry = try entry(id: id, in: context) else {
            throw PassiveHistoryError.entryNotFound
        }
        return entry
    }

    private func entry(id: UUID, in context: ModelContext) throws -> HistoryEntry? {
        var descriptor = FetchDescriptor<HistoryEntry>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        do {
            return try context.fetch(descriptor).first
        } catch {
            throw PassiveHistoryError.persistenceUnavailable
        }
    }

    private func save(_ context: ModelContext) throws {
        do {
            try context.save()
        } catch {
            throw PassiveHistoryError.persistenceUnavailable
        }
    }

    private static func validate(
        speakerRegions: [CapturedSpeakerRegion],
        durationMilliseconds: Int?
    ) throws {
        var previousEnd = 0
        for (index, region) in speakerRegions.enumerated() {
            guard region.startMilliseconds >= 0,
                region.endMilliseconds >= region.startMilliseconds,
                index == 0 || region.startMilliseconds >= previousEnd
            else {
                throw PassiveHistoryError.invalidRegionOrder
            }
            if region.isOverlap, region.speaker != .unresolved {
                throw PassiveHistoryError.invalidOverlapIdentity
            }
            if let durationMilliseconds, region.endMilliseconds > durationMilliseconds {
                throw PassiveHistoryError.regionOutsideCapture
            }
            previousEnd = region.endMilliseconds
        }
    }
}
