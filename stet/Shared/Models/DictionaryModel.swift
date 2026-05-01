import Foundation
import os
import SwiftData

nonisolated private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.openwhispr.Stet",
    category: "general"
)

nonisolated private let sharedDictionaryModelContainer: ModelContainer? = {
    do {
        return try DictionaryModel.makePersistentModelContainer()
    } catch {
        logger.error(
            "Failed to create DictionaryModel container. Falling back to UserDefaults-backed dictionary. error=\(error)"
        )
        return nil
    }
}()

nonisolated private let sharedLegacyDictionaryModelContainer: ModelContainer? = {
    do {
        return try DictionaryModel.makeLegacyPersistentModelContainerIfAvailable()
    } catch {
        logger.error(
            "Failed to create legacy DictionaryModel container for migration. error=\(error)"
        )
        return nil
    }
}()

@Model
final class DictionaryEntryRecord {
    @Attribute(.unique) var normalizedText: String = ""
    var displayText: String = ""
    var sortIndex: Int = 0

    init(displayText: String, normalizedText: String, sortIndex: Int) {
        self.displayText = displayText
        self.normalizedText = normalizedText
        self.sortIndex = sortIndex
    }
}

struct DictionaryModel: @unchecked Sendable {
    nonisolated private let modelContainer: ModelContainer?
    nonisolated private let legacyModelContainer: ModelContainer?
    private let defaultsStore: UserDefaultsStore

    nonisolated init() {
        self.init(
            modelContainer: sharedDictionaryModelContainer,
            legacyModelContainer: sharedLegacyDictionaryModelContainer,
            defaults: .standard
        )
    }

    nonisolated init(defaults: UserDefaults) {
        self.init(
            modelContainer: sharedDictionaryModelContainer,
            legacyModelContainer: sharedLegacyDictionaryModelContainer,
            defaults: defaults
        )
    }

    nonisolated init(
        modelContainer: ModelContainer?,
        legacyModelContainer: ModelContainer? = nil,
        defaults: UserDefaults
    ) {
        self.modelContainer = modelContainer
        self.legacyModelContainer = legacyModelContainer
        self.defaultsStore = UserDefaultsStore(defaults)
    }

    nonisolated func loadEntries() -> [String] {
        let defaultsEntries = Self.normalizeEntries(
            defaultsStore.stringArray(forKey: MacPreferences.personalDictionary) ?? []
        )

        guard let context = modelContext else {
            return defaultsEntries
        }

        do {
            let storedEntries = try fetchEntries(using: context)
            if !storedEntries.isEmpty {
                return storedEntries
            }
        } catch {
            logger.error(
                "Failed to fetch dictionary entries from SwiftData store. Falling back to UserDefaults-backed dictionary. error=\(error)"
            )
        }

        if !defaultsEntries.isEmpty {
            do {
                try replaceEntries(defaultsEntries, using: context)
                defaultsStore.removeObject(forKey: MacPreferences.personalDictionary)
            } catch {
                logger.error(
                    "Failed to migrate UserDefaults-backed dictionary entries into SwiftData store. error=\(error)"
                )
            }

            return defaultsEntries
        }

        guard let legacyContext = legacyModelContext else {
            return []
        }

        let legacyStoreEntries: [String]
        do {
            legacyStoreEntries = try fetchEntries(using: legacyContext)
        } catch {
            logger.error(
                "Failed to fetch dictionary entries from legacy SwiftData store. error=\(error)"
            )
            return []
        }

        guard !legacyStoreEntries.isEmpty else {
            return []
        }

        do {
            try replaceEntries(legacyStoreEntries, using: context)
        } catch {
            logger.error(
                "Failed to migrate dictionary entries from legacy SwiftData store. Falling back to UserDefaults-backed dictionary. error=\(error)"
            )
            defaultsStore.set(legacyStoreEntries, forKey: MacPreferences.personalDictionary)
        }

        return legacyStoreEntries
    }

    nonisolated func loadIsEnabled() -> Bool {
        defaultsStore.object(forKey: MacPreferences.personalDictionaryEnabled) as? Bool ?? true
    }

    nonisolated func saveEntries(_ entries: [String]) {
        let normalizedEntries = Self.normalizeEntries(entries)

        guard let context = modelContext else {
            defaultsStore.set(normalizedEntries, forKey: MacPreferences.personalDictionary)
            return
        }

        do {
            try replaceEntries(normalizedEntries, using: context)
            defaultsStore.removeObject(forKey: MacPreferences.personalDictionary)
        } catch {
            logger.error(
                "Failed to save dictionary entries to SwiftData store. Falling back to UserDefaults-backed dictionary. error=\(error)"
            )
            defaultsStore.set(normalizedEntries, forKey: MacPreferences.personalDictionary)
        }
    }

    nonisolated func saveIsEnabled(_ enabled: Bool) {
        defaultsStore.set(enabled, forKey: MacPreferences.personalDictionaryEnabled)
    }

    nonisolated func addEntries(from rawInput: String) -> [String] {
        let updatedEntries = loadEntries() + Self.words(from: rawInput)
        saveEntries(updatedEntries)
        return loadEntries()
    }

    nonisolated func removeEntry(_ entry: String) -> [String] {
        let normalizedLookupKey = Self.lookupKey(for: entry)
        let updatedEntries = loadEntries().filter {
            Self.lookupKey(for: $0) != normalizedLookupKey
        }
        saveEntries(updatedEntries)
        return updatedEntries
    }

    nonisolated func clear() {
        saveEntries([])
    }

    nonisolated static func words(from rawInput: String) -> [String] {
        normalizeEntries(
            rawInput
                .split(whereSeparator: { $0 == "," || $0 == "\n" })
                .map(String.init)
        )
    }

    nonisolated static func makeInMemoryModelContainer() throws -> ModelContainer {
        let schema = Schema([DictionaryEntryRecord.self])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )

        return try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
    }

    nonisolated static func makePersistentModelContainer(
        appSupportDirectory: URL? = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first,
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "NaichengDeng.Stet"
    ) throws -> ModelContainer {
        let schema = Schema([DictionaryEntryRecord.self])
        let configuration = ModelConfiguration(
            schema: schema,
            url: try persistentStoreURL(
                appSupportDirectory: appSupportDirectory,
                bundleIdentifier: bundleIdentifier
            )
        )

        return try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
    }

    nonisolated static func makeLegacyPersistentModelContainerIfAvailable(
        appSupportDirectory: URL? = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first
    ) throws -> ModelContainer? {
        guard let legacyStoreURL = legacyPersistentStoreURL(appSupportDirectory: appSupportDirectory),
            FileManager.default.fileExists(atPath: legacyStoreURL.path)
        else {
            return nil
        }

        let schema = Schema([DictionaryEntryRecord.self])
        let configuration = ModelConfiguration(
            schema: schema,
            url: legacyStoreURL
        )

        return try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
    }

    nonisolated private var modelContext: ModelContext? {
        guard let modelContainer else {
            return nil
        }

        return ModelContext(modelContainer)
    }

    nonisolated private var legacyModelContext: ModelContext? {
        guard let legacyModelContainer else {
            return nil
        }

        return ModelContext(legacyModelContainer)
    }

    nonisolated private func fetchEntries(using context: ModelContext) throws -> [String] {
        let descriptor = FetchDescriptor<DictionaryEntryRecord>(
            sortBy: [
                SortDescriptor(\.sortIndex),
                SortDescriptor(\.displayText),
            ]
        )

        let records = try context.fetch(descriptor)
        return records.map(\.displayText)
    }

    nonisolated private func replaceEntries(_ entries: [String], using context: ModelContext) throws {
        let normalizedEntries = Self.normalizeEntries(entries)
        let descriptor = FetchDescriptor<DictionaryEntryRecord>()
        let existingRecords = try context.fetch(descriptor)

        for record in existingRecords {
            context.delete(record)
        }

        for (index, entry) in normalizedEntries.enumerated() {
            context.insert(
                DictionaryEntryRecord(
                    displayText: entry,
                    normalizedText: Self.lookupKey(for: entry),
                    sortIndex: index
                )
            )
        }

        try context.save()
    }

    nonisolated private static func persistentStoreURL(
        appSupportDirectory: URL?,
        bundleIdentifier: String
    ) throws -> URL {
        guard let appSupportDirectory else {
            throw CocoaError(.fileNoSuchFile)
        }

        let directoryURL =
            appSupportDirectory
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
            .appendingPathComponent("SwiftData", isDirectory: true)

        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )

        return directoryURL.appendingPathComponent("PersonalDictionary.store")
    }

    nonisolated private static func legacyPersistentStoreURL(
        appSupportDirectory: URL?
    ) -> URL? {
        appSupportDirectory?.appendingPathComponent("default.store")
    }

    nonisolated private static func normalizeEntries(_ entries: [String]) -> [String] {
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

    nonisolated private static func lookupKey(for entry: String) -> String {
        entry
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
