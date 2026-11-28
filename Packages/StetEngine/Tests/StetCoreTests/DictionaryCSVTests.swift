import Foundation
import Testing

@testable import StetCore

struct DictionaryCSVTests {
    @Test func parsesQuotedFieldsEscapedQuotesAndCRLF() {
        let csv = "\"Apple, Inc.\",\"She said \"\"Hi\"\"\"\r\nStet,FunASR\r\n"
        let records = DictionaryCSV.parseRecords(from: csv)
        #expect(
            records == [
                GlossaryEntry(term: "Apple, Inc.", source: .manual),
                GlossaryEntry(term: "She said \"Hi\"", source: .manual),
                GlossaryEntry(term: "Stet", source: .manual),
                GlossaryEntry(term: "FunASR", source: .manual),
            ])
    }

    @Test func headerAwareImportExtractsTermAndSourceAndIgnoresExtraColumns() throws {
        let defaults = UserDefaults(suiteName: "StetCoreTests.CSVHeader.\(UUID().uuidString)")!
        let model = DictionaryModel(defaults: defaults, entriesKey: "dictionary.entries.\(UUID().uuidString)")
        defer { model.clear() }
        model.addAutomaticEntries(["python"])

        let csv = """
            Term,Source,Notes
            "Apple, Inc.",manual,"Company name"
            Python,manual,"Duplicate should be skipped"
            FunASR,automatic,"Learned term"
            CloudKit,,"Unknown source defaults to manual"
            """
        let result = try model.importEntries(from: csv, format: .csv)
        #expect(result == DictionaryImportResult(addedCount: 3, skippedCount: 1))
        #expect(
            model.loadRecords() == [
                GlossaryEntry(term: "python", source: .automatic),
                GlossaryEntry(term: "Apple, Inc.", source: .manual),
                GlossaryEntry(term: "FunASR", source: .automatic),
                GlossaryEntry(term: "CloudKit", source: .manual),
            ])
    }

    @Test func supportsChineseHeadersAndHeaderlessTermSourceRows() {
        let chineseCSV = "词条,来源,备注\n谌龙,manual,人名\nStet,automatic,产品\n"
        #expect(
            DictionaryCSV.parseRecords(from: chineseCSV) == [
                GlossaryEntry(term: "谌龙", source: .manual),
                GlossaryEntry(term: "Stet", source: .automatic),
            ])

        let headerlessCSV = "Stet,manual\nFunASR,automatic\n"
        #expect(
            DictionaryCSV.parseRecords(from: headerlessCSV) == [
                GlossaryEntry(term: "Stet", source: .manual),
                GlossaryEntry(term: "FunASR", source: .automatic),
            ])
    }

    @Test func exportAndReimportRoundTripsLosslessly() throws {
        let sourceDefaults = UserDefaults(suiteName: "StetCoreTests.CSVExport.\(UUID().uuidString)")!
        let sourceModel = DictionaryModel(
            defaults: sourceDefaults,
            entriesKey: "dictionary.entries.\(UUID().uuidString)"
        )
        defer { sourceModel.clear() }

        _ = try sourceModel.importEntries(
            from: #"""
                term,source
                "Apple, Inc.",manual
                "Quote ""Test""",manual
                FunASR,automatic
                谌龙,manual
                """#,
            format: .csv
        )

        let exportedData = sourceModel.exportCSVData()
        let exportedText = try DictionaryModel.importText(from: exportedData)
        #expect(exportedText.hasPrefix("term,source\n"))
        #expect(exportedText.contains("\"Apple, Inc.\",manual"))
        #expect(exportedText.contains("\"Quote \"\"Test\"\"\",manual"))

        let targetDefaults = UserDefaults(suiteName: "StetCoreTests.CSVReimport.\(UUID().uuidString)")!
        let targetModel = DictionaryModel(
            defaults: targetDefaults,
            entriesKey: "dictionary.entries.\(UUID().uuidString)"
        )
        defer { targetModel.clear() }

        let result = try targetModel.importEntries(from: exportedText, format: .csv)
        #expect(result == DictionaryImportResult(addedCount: 4, skippedCount: 0))
        #expect(targetModel.loadRecords() == sourceModel.loadRecords())
    }

    @Test func headerOnlyCSVIsRejectedAsEmpty() {
        let defaults = UserDefaults(suiteName: "StetCoreTests.CSVEmpty.\(UUID().uuidString)")!
        let model = DictionaryModel(defaults: defaults, entriesKey: "dictionary.entries.\(UUID().uuidString)")
        defer { model.clear() }

        #expect(throws: DictionaryImportError.empty) {
            try model.importEntries(from: "term,source\n,\n", format: .csv)
        }
    }

    @Test func infersFormatFromFileExtension() {
        #expect(DictionaryImportFormat.inferred(from: URL(fileURLWithPath: "/tmp/terms.csv")) == .csv)
        #expect(DictionaryImportFormat.inferred(from: URL(fileURLWithPath: "/tmp/TERMS.CSV")) == .csv)
        #expect(DictionaryImportFormat.inferred(from: URL(fileURLWithPath: "/tmp/terms.txt")) == .plainText)
    }
}
