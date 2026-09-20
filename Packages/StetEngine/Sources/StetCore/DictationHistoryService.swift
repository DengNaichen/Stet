import Foundation
import CoreData
import SwiftData

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
    private var initializationError: Error?
    private var pending: PendingSession?
    private var lastCommittedEntryID: UUID?
    private var stagedRawTextWithoutHotwords: String?

    // MARK: - Init

    private init() {
        do {
            self.container = try Self.makePersistentContainer()
        } catch {
            self.container = nil
            self.initializationError = error
        }
    }

    /// History owns a separate store so opening another feature's schema cannot remove its tables.
    static func makePersistentContainer(
        appSupportDirectory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0],
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "NaichengDeng.Stet"
    ) throws -> ModelContainer {
        let directory = appSupportDirectory.appendingPathComponent(bundleIdentifier)
            .appendingPathComponent("SwiftData", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent("History.store")
        let legacy = appSupportDirectory.appendingPathComponent("default.store")
        if !FileManager.default.fileExists(atPath: destination.path),
            FileManager.default.fileExists(atPath: legacy.path)
        {
            let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
                ofType: NSSQLiteStoreType, at: legacy, options: [NSReadOnlyPersistentStoreOption: true])
            let entities = metadata[NSStoreModelVersionHashesKey] as? [String: Any] ?? [:]
            if entities["HistoryEntry"] != nil {
                // Core Data copies a consistent store, including WAL transactions. Keep the original intact.
                let coordinator = NSPersistentStoreCoordinator(managedObjectModel: NSManagedObjectModel())
                try coordinator.replacePersistentStore(
                    at: destination, destinationOptions: nil,
                    withPersistentStoreFrom: legacy, sourceOptions: [NSReadOnlyPersistentStoreOption: true],
                    ofType: NSSQLiteStoreType)
            }
        }
        let schema = Schema([HistoryEntry.self])
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: destination)])
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
        let rawTextWithoutHotwords = session.rawTextWithoutHotwords
        let llmText = session.llmText
        let timestamp = session.timestamp

        Task.detached(priority: .background) {
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
            try? context.save()
        }
    }

    private func updateRawTextWithoutHotwords(id: UUID, text: String) {
        guard let container else { return }

        Task.detached(priority: .background) {
            for _ in 0..<20 {
                let context = ModelContext(container)
                var descriptor = FetchDescriptor<HistoryEntry>(
                    predicate: #Predicate { $0.id == id }
                )
                descriptor.fetchLimit = 1
                if let entry = try? context.fetch(descriptor).first {
                    entry.rawTextWithoutHotwords = text
                    try? context.save()
                    return
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
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
            throw initializationError ?? PassiveHistoryError.persistenceUnavailable
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
