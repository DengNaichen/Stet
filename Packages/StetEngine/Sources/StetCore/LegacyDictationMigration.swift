import CryptoKit
import Foundation
import SQLite3
import SwiftData

enum LegacyDictationMigration {
    static func migrate(into container: ModelContainer, directory: URL, appSupport: URL) throws {
        let marker = directory.appendingPathComponent("SyncedData.legacyMigrationV1")
        let exists = FileManager.default.fileExists(atPath:)
        guard !exists(marker.path) else { return }
        let history = directory.appendingPathComponent("History.store")
        let source = exists(history.path) ? history : appSupport.appendingPathComponent("default.store")
        let stats = directory.appendingPathComponent("DictationStats.store")
        guard exists(source.path) || exists(stats.path) else { return }

        let context = ModelContext(container)
        if exists(source.path) {
            var ids = Set(try context.fetch(FetchDescriptor<HistoryEntry>()).map(\.id))
            try read(source, table: "ZHISTORYENTRY") { row in
                guard let data = row.data("ZID"), data.count == 16, let date = row.date("ZTIMESTAMP"),
                    let text = row.string("ZRAWTEXT")
                else { throw CocoaError(.fileReadCorruptFile) }
                let id = UUID(uuid: data.withUnsafeBytes { $0.loadUnaligned(as: uuid_t.self) })
                guard ids.insert(id).inserted else { return }
                let entry = HistoryEntry(
                    id: id, timestamp: date, rawText: text,
                    rawTextWithoutHotwords: row.string("ZRAWTEXTWITHOUTHOTWORDS"),
                    llmText: row.string("ZLLMTEXT"), finalText: row.string("ZFINALTEXT"),
                    targetBundleID: row.string("ZTARGETBUNDLEID"), targetAppName: row.string("ZTARGETAPPNAME"),
                    captureStartedAt: row.date("ZCAPTURESTARTEDATSTORAGE"), captureEndedAt: row.date("ZCAPTUREENDEDAT"),
                    processingFailureCode: row.string("ZPROCESSINGFAILURECODE"))
                entry.statusRawValue = row.string("ZSTATUSRAWVALUE") ?? row.string("ZSTATUS") ?? entry.statusRawValue
                entry.captureModeRawValue = row.string("ZCAPTUREMODERAWVALUE") ?? entry.captureModeRawValue
                entry.processingStateRawValue = row.string("ZPROCESSINGSTATERAWVALUE") ?? entry.processingStateRawValue
                entry.speakerRegionsData = row.data("ZSPEAKERREGIONSDATA") ?? Data()
                context.insert(entry)
            }
        }
        if exists(stats.path) {
            var ids = Set(try context.fetch(FetchDescriptor<DictationSessionRecord>()).map(\.id))
            try read(stats, table: "ZDICTATIONSESSIONRECORD") { row in
                guard let date = row.date("ZSTARTEDAT"), let duration = row.double("ZDURATIONSECONDS"),
                    let count = row.integer("ZWORDCOUNT")
                else { throw CocoaError(.fileReadCorruptFile) }
                let record = DictationSessionRecord(
                    startedAt: date, durationSeconds: duration, wordCount: count,
                    targetBundleID: row.string("ZTARGETBUNDLEID"), targetAppName: row.string("ZTARGETAPPNAME"),
                    sourcePlatform: "macOS")
                record.id = deterministicID(record)
                if ids.insert(record.id).inserted { context.insert(record) }
            }
        }
        try context.save()
        try Data().write(to: marker, options: .atomic)
    }

    private static func deterministicID(_ record: DictationSessionRecord) -> UUID {
        var bytes = Data()
        func append(_ value: UInt64) {
            withUnsafeBytes(of: value.bigEndian) { bytes.append(contentsOf: $0) }
        }
        append(record.startedAt.timeIntervalSinceReferenceDate.bitPattern)
        append(record.durationSeconds.bitPattern)
        append(UInt64(bitPattern: Int64(record.wordCount)))
        for field in [record.targetBundleID ?? "", record.targetAppName ?? ""] {
            append(UInt64(field.utf8.count))
            bytes.append(contentsOf: field.utf8)
        }
        var digest = Array(SHA256.hash(data: bytes).prefix(16))
        digest[6] = (digest[6] & 0x0F) | 0x50
        digest[8] = (digest[8] & 0x3F) | 0x80
        return UUID(uuid: digest.withUnsafeBytes { $0.loadUnaligned(as: uuid_t.self) })
    }

    // The old default.store can belong to the dictionary. Inspect the catalog
    // before selecting a table, and leave SQLite in read-only mode throughout.
    private static func read(_ url: URL, table: String, visit: (Row) throws -> Void) throws {
        var db: OpaquePointer?
        let opened = sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil)
        defer { sqlite3_close(db) }
        func check(_ code: Int32) throws {
            guard code == SQLITE_OK else {
                throw NSError(
                    domain: "StetCore.LegacySQLite", code: Int(code),
                    userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(db))])
            }
        }
        try check(opened)
        func select(_ sql: String, body: (Row) throws -> Void) throws {
            var statement: OpaquePointer?
            try check(sqlite3_prepare_v2(db, sql, -1, &statement, nil))
            defer { sqlite3_finalize(statement) }
            let row = Row(statement: statement)
            var step = sqlite3_step(statement)
            while step == SQLITE_ROW {
                try body(row)
                step = sqlite3_step(statement)
            }
            if step != SQLITE_DONE { try check(step) }
        }
        var found = false
        try select("SELECT name FROM sqlite_master WHERE type='table' AND name='\(table)'") { _ in found = true }
        guard found else {
            if url.lastPathComponent == "default.store" { return }
            throw CocoaError(.fileReadCorruptFile)
        }
        try select("SELECT * FROM \(table)", body: visit)
    }

    private struct Row {
        let statement: OpaquePointer?
        let columns: [String: Int32]

        init(statement: OpaquePointer?) {
            self.statement = statement
            columns = Dictionary(
                uniqueKeysWithValues: (0..<sqlite3_column_count(statement)).map {
                    (String(cString: sqlite3_column_name(statement, $0)), $0)
                })
        }

        private func index(_ key: String) -> Int32? {
            columns[key].flatMap { sqlite3_column_type(statement, $0) == SQLITE_NULL ? nil : $0 }
        }

        func data(_ key: String) -> Data? {
            index(key).map {
                let size = Int(sqlite3_column_bytes(statement, $0))
                guard let bytes = sqlite3_column_blob(statement, $0) else { return Data() }
                return Data(bytes: bytes, count: size)
            }
        }

        func string(_ key: String) -> String? {
            index(key).flatMap { column in
                sqlite3_column_text(statement, column).map {
                    String(
                        decoding: UnsafeBufferPointer(start: $0, count: Int(sqlite3_column_bytes(statement, column))),
                        as: UTF8.self)
                }
            }
        }

        func double(_ key: String) -> Double? { index(key).map { sqlite3_column_double(statement, $0) } }
        func integer(_ key: String) -> Int? { index(key).map { Int(sqlite3_column_int64(statement, $0)) } }
        func date(_ key: String) -> Date? { double(key).map(Date.init(timeIntervalSinceReferenceDate:)) }
    }
}
