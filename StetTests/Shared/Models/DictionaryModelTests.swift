import Foundation
import SwiftData
import Testing

@testable import Stet

@Suite("Dictionary Model", .serialized)
struct DictionaryModelTests {
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

    private func makePersistentModel(
        appSupportDirectory: URL,
        bundleIdentifier: String = "com.example.Stet"
    ) throws -> ModelContainer {
        try DictionaryModel.makePersistentModelContainer(
            appSupportDirectory: appSupportDirectory,
            bundleIdentifier: bundleIdentifier
        )
    }

    private func makeLegacyModel(appSupportDirectory: URL) throws -> ModelContainer {
        let schema = Schema([DictionaryEntryRecord.self])
        let configuration = ModelConfiguration(
            schema: schema,
            url: appSupportDirectory.appendingPathComponent("default.store")
        )

        return try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
    }

    @Test func nilModelContainerFallsBackToUserDefaultsStorage() {
        let defaults = TestSupport.makeUserDefaults()
        let subject = DictionaryModel(
            modelContainer: nil,
            defaults: defaults
        )

        subject.saveEntries([" OpenAI ", "Groq", "openai"])

        #expect(subject.loadEntries() == ["OpenAI", "Groq"])
        #expect(defaults.stringArray(forKey: MacPreferences.personalDictionary) == ["OpenAI", "Groq"])
    }

    @Test func persistentStoreUsesAppSpecificDirectoryAndPersistsAcrossInstances() throws {
        let appSupportDirectory = try makeAppSupportDirectory()
        defer { try? FileManager.default.removeItem(at: appSupportDirectory) }

        let container = try makePersistentModel(appSupportDirectory: appSupportDirectory)
        let subject = DictionaryModel(
            modelContainer: container,
            defaults: TestSupport.makeUserDefaults()
        )

        subject.saveEntries(["OpenAI", "Groq"])

        let secondSubject = DictionaryModel(
            modelContainer: try makePersistentModel(appSupportDirectory: appSupportDirectory),
            defaults: TestSupport.makeUserDefaults()
        )

        let expectedStoreURL =
            appSupportDirectory
            .appendingPathComponent("com.example.Stet", isDirectory: true)
            .appendingPathComponent("SwiftData", isDirectory: true)
            .appendingPathComponent("PersonalDictionary.store")

        #expect(FileManager.default.fileExists(atPath: expectedStoreURL.path))
        #expect(secondSubject.loadEntries() == ["OpenAI", "Groq"])
    }

    @Test func loadEntriesMigratesLegacyDefaultStoreIntoCurrentStore() throws {
        let appSupportDirectory = try makeAppSupportDirectory()
        defer { try? FileManager.default.removeItem(at: appSupportDirectory) }

        let legacyContainer = try makeLegacyModel(appSupportDirectory: appSupportDirectory)
        let legacyContext = ModelContext(legacyContainer)
        legacyContext.insert(
            DictionaryEntryRecord(
                displayText: "Cursor",
                normalizedText: "cursor",
                sortIndex: 0
            )
        )
        legacyContext.insert(
            DictionaryEntryRecord(
                displayText: "OpenAI",
                normalizedText: "openai",
                sortIndex: 1
            )
        )
        try legacyContext.save()

        guard
            let migratedLegacyContainer = try DictionaryModel.makeLegacyPersistentModelContainerIfAvailable(
                appSupportDirectory: appSupportDirectory
            )
        else {
            Issue.record("Expected legacy dictionary store to be available for migration.")
            return
        }

        let subject = DictionaryModel(
            modelContainer: try makePersistentModel(appSupportDirectory: appSupportDirectory),
            legacyModelContainer: migratedLegacyContainer,
            defaults: TestSupport.makeUserDefaults()
        )

        #expect(subject.loadEntries() == ["Cursor", "OpenAI"])

        let secondSubject = DictionaryModel(
            modelContainer: try makePersistentModel(appSupportDirectory: appSupportDirectory),
            defaults: TestSupport.makeUserDefaults()
        )

        #expect(secondSubject.loadEntries() == ["Cursor", "OpenAI"])
    }
}
