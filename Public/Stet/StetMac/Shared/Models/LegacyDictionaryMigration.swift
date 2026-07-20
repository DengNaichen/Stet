import Foundation
import os
import StetCore
import SwiftData

nonisolated private let legacyDictionaryLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.openwhispr.Stet",
    category: "general"
)

@Model
final class LegacyDictionaryEntryRecord {
    @Attribute(.unique) var normalizedText: String = ""
    var displayText: String = ""
    var sortIndex: Int = 0

    init(displayText: String, normalizedText: String, sortIndex: Int) {
        self.displayText = displayText
        self.normalizedText = normalizedText
        self.sortIndex = sortIndex
    }
}

enum LegacyDictionaryMigration {
    private static let migrationVersionKey = "mac.personalDictionaryMigrationVersion"
    private static let currentMigrationVersion = 1

    nonisolated static func migrateIfNeeded(
        defaults: UserDefaults = .standard,
        dictionaryModel: DictionaryModel = DictionaryModel()
    ) {
        migrateIfNeeded(
            defaults: defaults,
            dictionaryModel: dictionaryModel,
            appSupportDirectory: FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first,
            bundleIdentifier: Bundle.main.bundleIdentifier ?? "NaichengDeng.Stet"
        )
    }

    nonisolated static func migrateIfNeededForTests(
        defaults: UserDefaults,
        dictionaryModel: DictionaryModel,
        appSupportDirectory: URL?,
        bundleIdentifier: String
    ) {
        migrateIfNeeded(
            defaults: defaults,
            dictionaryModel: dictionaryModel,
            appSupportDirectory: appSupportDirectory,
            bundleIdentifier: bundleIdentifier
        )
    }

    private static func migrateIfNeeded(
        defaults: UserDefaults,
        dictionaryModel: DictionaryModel,
        appSupportDirectory: URL?,
        bundleIdentifier: String
    ) {
        guard defaults.integer(forKey: migrationVersionKey) < currentMigrationVersion else {
            return
        }

        let migratedEntries = loadLegacyEntries(
            defaults: defaults,
            appSupportDirectory: appSupportDirectory,
            bundleIdentifier: bundleIdentifier
        )
        if !migratedEntries.isEmpty, dictionaryModel.loadEntries().isEmpty {
            dictionaryModel.saveEntries(migratedEntries)
        }

        defaults.removeObject(forKey: MacPreferences.personalDictionary)
        defaults.set(currentMigrationVersion, forKey: migrationVersionKey)
    }

    private static func loadLegacyEntries(
        defaults: UserDefaults,
        appSupportDirectory: URL?,
        bundleIdentifier: String
    ) -> [String] {
        let defaultsEntries = DictionaryModel.words(
            from: (defaults.stringArray(forKey: MacPreferences.personalDictionary) ?? []).joined(separator: "\n")
        )
        if !defaultsEntries.isEmpty {
            return defaultsEntries
        }

        if let currentStoreEntries = loadEntriesFromPersistentStore(
            legacy: false,
            appSupportDirectory: appSupportDirectory,
            bundleIdentifier: bundleIdentifier
        ), !currentStoreEntries.isEmpty {
            return currentStoreEntries
        }

        return loadEntriesFromPersistentStore(
            legacy: true,
            appSupportDirectory: appSupportDirectory,
            bundleIdentifier: bundleIdentifier
        ) ?? []
    }

    private static func loadEntriesFromPersistentStore(
        legacy: Bool,
        appSupportDirectory: URL?,
        bundleIdentifier: String
    ) -> [String]? {
        let storeURL: URL?
        do {
            storeURL =
                try legacy
                ? legacyPersistentStoreURL(appSupportDirectory: appSupportDirectory)
                : persistentStoreURL(
                    appSupportDirectory: appSupportDirectory,
                    bundleIdentifier: bundleIdentifier
                )
        } catch {
            legacyDictionaryLogger.error(
                "Failed to build legacy dictionary store URL. error=\(error)"
            )
            return nil
        }

        guard let storeURL, FileManager.default.fileExists(atPath: storeURL.path) else {
            return nil
        }

        do {
            let schema = Schema([LegacyDictionaryEntryRecord.self])
            let configuration = ModelConfiguration(schema: schema, url: storeURL)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let context = ModelContext(container)
            let descriptor = FetchDescriptor<LegacyDictionaryEntryRecord>(
                sortBy: [
                    SortDescriptor(\.sortIndex),
                    SortDescriptor(\.displayText),
                ]
            )
            let records = try context.fetch(descriptor)
            return records.map(\.displayText)
        } catch {
            legacyDictionaryLogger.error(
                "Failed to load legacy dictionary entries from SwiftData store. error=\(error)"
            )
            return nil
        }
    }

    private static func persistentStoreURL(
        appSupportDirectory: URL?,
        bundleIdentifier: String
    ) throws -> URL {
        guard let appSupportDirectory else {
            throw CocoaError(.fileNoSuchFile)
        }

        return
            appSupportDirectory
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
            .appendingPathComponent("SwiftData", isDirectory: true)
            .appendingPathComponent("PersonalDictionary.store")
    }

    private static func legacyPersistentStoreURL(
        appSupportDirectory: URL?
    ) throws -> URL {
        guard let appSupportDirectory else {
            throw CocoaError(.fileNoSuchFile)
        }

        return appSupportDirectory.appendingPathComponent("default.store")
    }
}
