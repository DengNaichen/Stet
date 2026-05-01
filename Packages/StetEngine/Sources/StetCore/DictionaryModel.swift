import Foundation

public extension Notification.Name {
    static let dictionaryDidSync = Notification.Name("StetCore.DictionaryDidSync")
}

public final class SyncedDictionaryStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let cloudStore: NSUbiquitousKeyValueStore
    private let entriesKey: String
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
        self.notificationCenter = notificationCenter
        self.changeNotification = changeNotification
        self.cloudObserver = notificationCenter.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloudStore,
            queue: nil
        ) { [defaults, cloudStore, entriesKey, notificationCenter, changeNotification] _ in
            let entries = Self.normalizedEntries(
                cloudStore.array(forKey: entriesKey) as? [String] ?? []
            )
            defaults.set(entries, forKey: entriesKey)
            notificationCenter.post(
                name: changeNotification,
                object: nil,
                userInfo: ["entries": entries]
            )
        }

        cloudStore.synchronize()
    }

    deinit {
        notificationCenter.removeObserver(cloudObserver)
    }

    public func loadEntries() -> [String] {
        let cloudEntries = Self.normalizedEntries(
            cloudStore.array(forKey: entriesKey) as? [String] ?? []
        )
        if !cloudEntries.isEmpty {
            defaults.set(cloudEntries, forKey: entriesKey)
            return cloudEntries
        }

        return Self.normalizedEntries(defaults.stringArray(forKey: entriesKey) ?? [])
    }

    public func saveEntries(_ entries: [String]) {
        let normalizedEntries = Self.normalizedEntries(entries)
        defaults.set(normalizedEntries, forKey: entriesKey)
        cloudStore.set(normalizedEntries, forKey: entriesKey)
        cloudStore.synchronize()
        notificationCenter.post(
            name: changeNotification,
            object: nil,
            userInfo: ["entries": normalizedEntries]
        )
    }

    private static func normalizedEntries(_ entries: [String]) -> [String] {
        DictionaryModel.normalizedEntries(entries)
    }
}

public struct DictionaryModel: Sendable {
    private let syncedStore: SyncedDictionaryStore
    private let defaults: UserDefaults
    private let enabledKey: String

    public init(
        defaults: UserDefaults = .standard,
        syncedStore: SyncedDictionaryStore? = nil,
        entriesKey: String = "dictionary.entries",
        enabledKey: String = "dictionary.enabled"
    ) {
        self.defaults = defaults
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

    public func loadIsEnabled() -> Bool {
        defaults.object(forKey: enabledKey) as? Bool ?? true
    }

    public func saveEntries(_ entries: [String]) {
        syncedStore.saveEntries(entries)
    }

    public func saveIsEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: enabledKey)
    }

    public func addEntries(from rawInput: String) -> [String] {
        let updatedEntries = loadEntries() + Self.words(from: rawInput)
        saveEntries(updatedEntries)
        return loadEntries()
    }

    public func removeEntry(_ entry: String) -> [String] {
        let normalizedLookupKey = Self.lookupKey(for: entry)
        let updatedEntries = loadEntries().filter {
            Self.lookupKey(for: $0) != normalizedLookupKey
        }
        saveEntries(updatedEntries)
        return updatedEntries
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
                entry
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
        entry
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
