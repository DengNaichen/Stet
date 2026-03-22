import Foundation
import SwiftData

nonisolated private let sharedDictionaryModelContainer: ModelContainer? = {
    let schema = Schema([DictionaryEntryRecord.self])
    let configuration = ModelConfiguration(schema: schema)

    do {
        return try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
    } catch {
        AppLogger.error(
            "Failed to create DictionaryModel container. Falling back to UserDefaults-backed dictionary. error=\(error)"
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
    private let defaultsStore: UserDefaultsStore

    nonisolated init() {
        self.init(
            modelContainer: sharedDictionaryModelContainer,
            defaults: .standard
        )
    }

    nonisolated init(defaults: UserDefaults) {
        self.init(
            modelContainer: sharedDictionaryModelContainer,
            defaults: defaults
        )
    }

    nonisolated init(
        modelContainer: ModelContainer?,
        defaults: UserDefaults
    ) {
        self.modelContainer = modelContainer
        self.defaultsStore = UserDefaultsStore(defaults)
    }

    nonisolated func loadEntries() -> [String] {
        guard let context = modelContext else {
            return Self.normalizeEntries(
                defaultsStore.stringArray(forKey: MacPreferences.personalDictionary) ?? []
            )
        }

        let storedEntries = fetchEntries(using: context)

        guard storedEntries.isEmpty else {
            return storedEntries
        }

        let legacyEntries = Self.normalizeEntries(
            defaultsStore.stringArray(forKey: MacPreferences.personalDictionary) ?? []
        )

        guard !legacyEntries.isEmpty else {
            return []
        }

        replaceEntries(legacyEntries, using: context)
        defaultsStore.removeObject(forKey: MacPreferences.personalDictionary)
        return legacyEntries
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

        replaceEntries(entries, using: context)
        defaultsStore.removeObject(forKey: MacPreferences.personalDictionary)
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

    nonisolated private var modelContext: ModelContext? {
        guard let modelContainer else {
            return nil
        }

        return ModelContext(modelContainer)
    }

    nonisolated private func fetchEntries(using context: ModelContext) -> [String] {
        let descriptor = FetchDescriptor<DictionaryEntryRecord>(
            sortBy: [
                SortDescriptor(\.sortIndex),
                SortDescriptor(\.displayText),
            ]
        )

        guard let records = try? context.fetch(descriptor) else {
            return []
        }

        return records.map(\.displayText)
    }

    nonisolated private func replaceEntries(_ entries: [String], using context: ModelContext) {
        let normalizedEntries = Self.normalizeEntries(entries)
        let descriptor = FetchDescriptor<DictionaryEntryRecord>()
        let existingRecords = (try? context.fetch(descriptor)) ?? []

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

        try? context.save()
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
