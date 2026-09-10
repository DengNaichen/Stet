import Foundation

public extension Notification.Name {
    static let dictionaryDidSync = Notification.Name("StetCore.DictionaryDidSync")
}

/// `UserDefaults` supports access from multiple threads and tasks, but is not
/// declared `Sendable` by Foundation. Keep that unchecked boundary limited to
/// the enabled-flag operations used by `DictionaryModel`.
private final class DictionaryDefaultsStore: @unchecked Sendable {
    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func loadIsEnabled(forKey key: String) -> Bool {
        defaults.object(forKey: key) as? Bool ?? true
    }

    func saveIsEnabled(_ enabled: Bool, forKey key: String) {
        defaults.set(enabled, forKey: key)
    }
}

public final class SyncedDictionaryStore: @unchecked Sendable {
    private static let lock = NSRecursiveLock()
    private let defaults: UserDefaults
    private let cloudStore: NSUbiquitousKeyValueStore
    private let entriesKey: String
    private let provenanceKey: String
    private let notificationCenter: NotificationCenter
    private let changeNotification: Notification.Name
    private let cloudObserver: NSObjectProtocol

    public init(
        defaults: UserDefaults = .standard,
        cloudStore: NSUbiquitousKeyValueStore = .default,
        entriesKey: String = "dictionary.entries",
        notificationCenter: NotificationCenter = .default,
        changeNotification: Notification.Name = .dictionaryDidSync
    ) {
        self.defaults = defaults
        self.cloudStore = cloudStore
        self.entriesKey = entriesKey
        let provenanceKey = entriesKey + ".provenance.v1"
        self.provenanceKey = provenanceKey
        self.notificationCenter = notificationCenter
        self.changeNotification = changeNotification
        self.cloudObserver = notificationCenter.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloudStore,
            queue: nil
        ) { [defaults, cloudStore, entriesKey, provenanceKey, notificationCenter, changeNotification] notification in
            if let keys = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String],
                !keys.contains(entriesKey), !keys.contains(provenanceKey)
            {
                return
            }
            Self.lock.lock()
            let sources = cloudStore.dictionary(forKey: provenanceKey) as? [String: String] ?? [:]
            let records = Self.decodeRecords(cloudStore.array(forKey: entriesKey) ?? [], sources: sources)
            defaults.set(records.map(\.term), forKey: entriesKey)
            defaults.set(sources, forKey: provenanceKey)
            Self.lock.unlock()
            notificationCenter.post(
                name: changeNotification, object: nil, userInfo: ["entries": records.map(\.term)]
            )
        }

        cloudStore.synchronize()
    }

    deinit {
        notificationCenter.removeObserver(cloudObserver)
    }

    public func loadEntries() -> [String] { loadRecords().map(\.term) }

    public func loadRecords() -> [GlossaryEntry] {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        return readRecords()
    }

    private func readRecords() -> [GlossaryEntry] {
        // An explicitly empty cloud array is a synced deletion, not a cache miss.
        if let cloudEntries = cloudStore.array(forKey: entriesKey) {
            let sources = cloudStore.dictionary(forKey: provenanceKey) as? [String: String] ?? [:]
            let records = Self.decodeRecords(cloudEntries, sources: sources)
            defaults.set(records.map(\.term), forKey: entriesKey)
            defaults.set(sources, forKey: provenanceKey)
            return records
        }
        return Self.decodeRecords(
            defaults.array(forKey: entriesKey) ?? [],
            sources: defaults.dictionary(forKey: provenanceKey) as? [String: String] ?? [:])
    }

    public func saveEntries(_ entries: [String]) {
        updateRecords { existing in
            let sources = Dictionary(uniqueKeysWithValues: existing.map { ($0.term.lowercased(), $0.source) })
            return DictionaryModel.normalizedEntries(entries).map {
                GlossaryEntry(term: $0, source: sources[$0.lowercased()] ?? .manual)
            }
        }
    }

    @discardableResult
    func updateRecords(_ update: ([GlossaryEntry]) -> [GlossaryEntry]) -> [GlossaryEntry] {
        Self.lock.lock()
        let records = GlossaryEntry.normalized(update(readRecords()))
        // Keep the original text-array wire format; provenance is an additive sidecar.
        let sources = Dictionary(uniqueKeysWithValues: records.map { ($0.term, $0.source.rawValue) })
        defaults.set(records.map(\.term), forKey: entriesKey)
        defaults.set(sources, forKey: provenanceKey)
        cloudStore.set(sources, forKey: provenanceKey)
        cloudStore.set(records.map(\.term), forKey: entriesKey)
        cloudStore.synchronize()
        Self.lock.unlock()
        // Notify outside the lock; a main-queue observer may read from another thread.
        notificationCenter.post(
            name: changeNotification, object: nil, userInfo: ["entries": records.map(\.term)]
        )
        return records
    }

    private static func decodeRecords(_ entries: [Any], sources: [String: String]) -> [GlossaryEntry] {
        GlossaryEntry.normalized(
            entries.compactMap { value in
                if let term = value as? String {
                    return .init(term: term, source: GlossaryEntry.Source(rawValue: sources[term] ?? "") ?? .manual)
                }
                guard let record = value as? [String: String], let term = record["term"] else { return nil }
                return .init(term: term, source: GlossaryEntry.Source(rawValue: record["source"] ?? "") ?? .manual)
            })
    }
}

public struct DictionaryModel: Sendable {
    private let syncedStore: SyncedDictionaryStore
    private let defaultsStore: DictionaryDefaultsStore
    private let enabledKey: String

    public init(
        defaults: UserDefaults = .standard,
        syncedStore: SyncedDictionaryStore? = nil,
        entriesKey: String = "dictionary.entries",
        enabledKey: String = "dictionary.enabled"
    ) {
        self.defaultsStore = DictionaryDefaultsStore(defaults: defaults)
        self.enabledKey = enabledKey
        self.syncedStore =
            syncedStore
            ?? SyncedDictionaryStore(
                defaults: defaults,
                entriesKey: entriesKey
            )
    }

    public func loadEntries() -> [String] {
        syncedStore.loadEntries()
    }

    public func loadRecords() -> [GlossaryEntry] { syncedStore.loadRecords() }

    public func loadIsEnabled() -> Bool {
        defaultsStore.loadIsEnabled(forKey: enabledKey)
    }

    public func saveEntries(_ entries: [String]) {
        syncedStore.saveEntries(entries)
    }

    public func saveIsEnabled(_ enabled: Bool) {
        defaultsStore.saveIsEnabled(enabled, forKey: enabledKey)
    }

    public func addEntries(from rawInput: String) -> [String] {
        syncedStore.updateRecords {
            GlossaryEntry.merging($0, terms: Self.words(from: rawInput), source: .manual)
        }.map(\.term)
    }

    @discardableResult
    public func addAutomaticEntries(_ terms: [String]) -> [GlossaryEntry] {
        guard loadIsEnabled(), !terms.isEmpty else { return loadRecords() }
        return syncedStore.updateRecords { GlossaryEntry.merging($0, terms: terms, source: .automatic) }
    }

    public func removeEntry(_ entry: String) -> [String] {
        let key = Self.lookupKey(for: entry)
        return syncedStore.updateRecords { $0.filter { Self.lookupKey(for: $0.term) != key } }.map(\.term)
    }

    public func clear() {
        saveEntries([])
    }

    public static func words(from rawInput: String) -> [String] {
        normalizedEntries(
            rawInput
                .split(whereSeparator: { $0 == "," || $0 == "\n" })
                .map(String.init)
        )
    }

    static func normalizedEntries(_ entries: [String]) -> [String] {
        var normalizedEntries: [String] = []
        var seenEntries = Set<String>()

        for entry in entries {
            let normalizedEntry =
                entry.precomposedStringWithCanonicalMapping
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !normalizedEntry.isEmpty else { continue }

            let lookupKey = lookupKey(for: normalizedEntry)
            guard !seenEntries.contains(lookupKey) else { continue }

            seenEntries.insert(lookupKey)
            normalizedEntries.append(normalizedEntry)
        }

        return normalizedEntries
    }

    static func lookupKey(for entry: String) -> String {
        entry.precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
