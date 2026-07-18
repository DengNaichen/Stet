import Foundation
import SwiftData
import Testing
import StetCore

@testable import Stet

@Suite("Legacy Dictionary Migration", .serialized)
struct LegacyDictionaryMigrationTests {
    private func makeAppSupportDirectory() throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
        return directoryURL
    }

    @Test func migrationMovesLegacyDefaultStoreEntriesIntoSharedDictionary() throws {
        let appSupportDirectory = try makeAppSupportDirectory()
        defer { try? FileManager.default.removeItem(at: appSupportDirectory) }

        let legacyStoreURL = appSupportDirectory.appendingPathComponent("default.store")
        let schema = Schema([LegacyDictionaryEntryRecord.self])
        let configuration = ModelConfiguration(schema: schema, url: legacyStoreURL)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        context.insert(
            LegacyDictionaryEntryRecord(
                displayText: "Cursor",
                normalizedText: "cursor",
                sortIndex: 0
            )
        )
        context.insert(
            LegacyDictionaryEntryRecord(
                displayText: "OpenAI",
                normalizedText: "openai",
                sortIndex: 1
            )
        )
        try context.save()

        let defaults = TestSupport.makeUserDefaults()
        let sharedDefaults = TestSupport.makeUserDefaults()
        let dictionaryModel = DictionaryModel(
            defaults: sharedDefaults,
            entriesKey: "dictionary.entries.\(UUID().uuidString)",
            enabledKey: "dictionary.enabled.\(UUID().uuidString)"
        )

        LegacyDictionaryMigration.migrateIfNeededForTests(
            defaults: defaults,
            dictionaryModel: dictionaryModel,
            appSupportDirectory: appSupportDirectory,
            bundleIdentifier: "com.example.Stet"
        )

        #expect(dictionaryModel.loadEntries() == ["Cursor", "OpenAI"])
    }
}
