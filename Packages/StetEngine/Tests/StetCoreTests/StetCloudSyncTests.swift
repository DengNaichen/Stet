import Foundation
import Security
import SwiftData
import Testing

@testable import StetCore

struct StetCloudSyncTests {
    @Test func sharedKeychainQueries() {
        let store = SharedKeychainSecretStore.iOS()
        let account = DictationCredentialAccount.apiKey(for: .openAI)
        #expect(account == "openai.api_key")
        #expect(DictationCredentialAccount.legacyIOSAPIKey(for: .openAI) == "rewrite.apikey.openai")
        let query = store.query(forAccount: account, synchronizable: true)
        #expect(query[kSecAttrAccessGroup as String] as? String == "67BL3M4FPS.NaichengDeng.Stet.shared")
        #expect(query[kSecAttrService as String] as? String == "NaichengDeng.Stet.credentials")
        #expect(query[kSecAttrAccount as String] as? String == account)
        #expect(query[kSecUseDataProtectionKeychain as String] as? Bool == true)
        #expect(query[kSecAttrSynchronizable as String] as? Bool == true)
        #expect(
            store.query(forAccount: account, synchronizable: false)[kSecAttrSynchronizable as String] as? Bool == false)
        #expect(
            store.writeAttributes("test")[kSecAttrAccessible as String] as? String == kSecAttrAccessibleAfterFirstUnlock
                as String)
        #expect(
            SharedKeychainSecretStore(accessGroup: nil).query(forAccount: account, synchronizable: nil)[
                kSecAttrAccessGroup as String] == nil)
    }

    @Test func unifiedDictionaryMergesOnceAndRespectsCloudDeletion() {
        let name = UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let key = "dictionary.entries"
        let cloud = CloudDictionary()
        defaults.set([" Local ", "swift"], forKey: key)
        cloud.set(["Swift", "Remote"], forKey: key)
        cloud.set(["Swift": "automatic"], forKey: key + ".provenance.v1")
        let store = SyncedDictionaryStore(defaults: defaults, cloud: cloud, entriesKey: key)
        #expect(
            store.loadRecords() == [
                .init(term: "swift", source: .manual), .init(term: "Remote", source: .manual),
                .init(term: "Local", source: .manual),
            ])
        #expect(cloud.array(forKey: key) as? [String] == ["swift", "Remote", "Local"])
        #expect(defaults.bool(forKey: "dictionary.kvs.unifiedMergeV1"))
        cloud.set([String](), forKey: key)
        #expect(store.loadRecords().isEmpty)
        #expect(defaults.stringArray(forKey: key) == [])
    }

    @Test func missingCloudDictionaryReceivesLocalCopy() {
        let name = UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let key = "dictionary.entries"
        let cloud = CloudDictionary()
        defaults.set(["Local"], forKey: key)
        _ = SyncedDictionaryStore(defaults: defaults, cloud: cloud, entriesKey: key)
        #expect(cloud.array(forKey: key) as? [String] == ["Local"])
        #expect(defaults.bool(forKey: "dictionary.kvs.unifiedMergeV1"))
    }

    @MainActor
    @Test func oldHistoryStatusAndPassiveMetadataSurviveMigration() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("test/SwiftData")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let schema = Schema([LegacySchema.HistoryEntry.self])
        let config = ModelConfiguration(
            schema: schema, url: directory.appendingPathComponent("History.store"),
            cloudKitDatabase: .none)
        let legacy = try ModelContainer(for: schema, configurations: [config])
        let source = LegacySchema.HistoryEntry()
        let context = ModelContext(legacy)
        context.insert(source)
        try context.save()
        let container = try StetCloudDataContainer.makePersistentContainer(
            appSupportDirectory: root, bundleIdentifier: "test", cloudKitEnabled: false)
        let migrated = try #require(DictationHistoryService(container: container).fetchRecent().first)
        #expect(migrated.id == source.id)
        #expect(migrated.timestamp == source.timestamp)
        #expect(migrated.status == .clipboardPending)
        #expect(migrated.captureMode == .passive)
        #expect(migrated.processingState == .failed)
        #expect(migrated.speakerRegionsData == source.speakerRegionsData)
        #expect(try context.fetchCount(FetchDescriptor<LegacySchema.HistoryEntry>()) == 1)
    }

    @MainActor
    @Test func completedSessionDoesNotReplacePendingCapture() async throws {
        let container = try StetCloudDataContainer.makeInMemoryContainer()
        let history = DictationHistoryService(container: container)
        history.recordRaw("pending")
        let date = Date(timeIntervalSinceReferenceDate: 100)
        let id = try #require(
            history.recordCompleted(
                rawText: " raw ", llmText: "rewrite", finalText: "delivered",
                targetAppName: "Editor", timestamp: date))
        #expect(history.commitPending() != nil)
        await history.waitForWrites()
        let entries = try history.fetchRecent()
        #expect(entries.count == 2)
        let completed = try #require(entries.first { $0.id == id })
        #expect(completed.status == .completed)
        #expect(completed.rawText == "raw")
        #expect(completed.llmText == "rewrite")
        #expect(completed.finalText == "delivered")
        #expect(completed.timestamp == date)
        #expect(completed.targetAppName == "Editor")
    }

    @Test func statsMigrationIsRepeatableAndCountsDistinctIDs() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("test/SwiftData")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let schema = Schema([DictationSessionRecord.self])
        let config = ModelConfiguration(
            schema: schema, url: directory.appendingPathComponent("DictationStats.store"),
            cloudKitDatabase: .none)
        let legacy = try ModelContainer(for: schema, configurations: [config])
        let date = Date(timeIntervalSinceReferenceDate: 100)
        DictationStatsModel(modelContainer: legacy).record(startedAt: date, durationSeconds: 2, wordCount: 3)
        let container = try StetCloudDataContainer.makePersistentContainer(
            appSupportDirectory: root,
            bundleIdentifier: "test", cloudKitEnabled: false)
        let context = ModelContext(container)
        let records = try context.fetch(FetchDescriptor<DictationSessionRecord>())
        let first = try #require(records.first)
        #expect(records.count == 1)
        #expect(first.sourcePlatform == "macOS")
        try FileManager.default.removeItem(at: directory.appendingPathComponent("SyncedData.legacyMigrationV1"))
        try LegacyDictationMigration.migrate(into: container, directory: directory, appSupport: root)
        #expect(try context.fetchCount(FetchDescriptor<DictationSessionRecord>()) == 1)
        let duplicate = DictationSessionRecord(startedAt: date, durationSeconds: 2, wordCount: 3)
        duplicate.id = first.id
        context.insert(duplicate)
        try context.save()
        #expect(DictationStatsModel(modelContainer: container).allTimeTotalWordCount() == 3)
        #expect(try ModelContext(legacy).fetchCount(FetchDescriptor<DictationSessionRecord>()) == 1)
    }
}

private final class CloudDictionary: DictionaryCloudStore {
    var values: [String: Any] = [:]
    func array(forKey key: String) -> [Any]? { values[key] as? [Any] }
    func dictionary(forKey key: String) -> [String: Any]? { values[key] as? [String: Any] }
    func set(_ value: Any?, forKey key: String) { values[key] = value }
    func synchronize() -> Bool { true }
}

private enum LegacySchema {
    @Model
    final class HistoryEntry {
        var id: UUID = UUID()
        var timestamp: Date = Date(timeIntervalSinceReferenceDate: 100)
        var rawText: String = "raw"
        var status: HistoryEntryStatus = HistoryEntryStatus.clipboardPending
        var captureModeRawValue: String = "passive"
        var processingStateRawValue: String = "failed"
        var speakerRegionsData: Data = Data([1, 2, 3])

        init() {}
    }
}
