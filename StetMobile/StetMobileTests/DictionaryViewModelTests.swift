import Foundation
import StetCore
import Testing

@testable import StetMobile

@MainActor
struct DictionaryViewModelTests {
    @Test func importsCSVWithHeadersQuotesAndDuplicatesAndExportsRoundTrip() throws {
        let suiteName = "StetMobileTests.Dictionary.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let model = DictionaryModel(
            defaults: defaults,
            entriesKey: "dictionary.entries.\(UUID().uuidString)",
            enabledKey: "dictionary.enabled.\(UUID().uuidString)"
        )
        defer { model.clear() }
        model.saveEntries(["Stet"])

        let viewModel = DictionaryViewModel(model: model)
        viewModel.load()

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("stet-mobile-dict-\(UUID().uuidString).csv")
        defer { try? FileManager.default.removeItem(at: url) }
        let csv = """
            term,source,notes
            "Apple, Inc.",manual,"Brand"
            Stet,manual,"Duplicate"
            CloudKit,automatic,"Sync"
            """
        try Data(csv.utf8).write(to: url)

        viewModel.importEntries(from: url)

        #expect(viewModel.allWords == ["Stet", "Apple, Inc.", "CloudKit"])
        #expect(viewModel.importAlert == .success(added: 2, skipped: 1))

        let exported = try DictionaryModel.importText(from: viewModel.exportCSVData())
        #expect(exported == "term,source\nStet,manual\n\"Apple, Inc.\",manual\nCloudKit,automatic\n")
    }

    @Test func reportsErrorForEmptyCSVImport() throws {
        let suiteName = "StetMobileTests.DictionaryEmpty.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let model = DictionaryModel(
            defaults: defaults,
            entriesKey: "dictionary.entries.\(UUID().uuidString)",
            enabledKey: "dictionary.enabled.\(UUID().uuidString)"
        )
        defer { model.clear() }

        let viewModel = DictionaryViewModel(model: model)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("stet-mobile-empty-\(UUID().uuidString).csv")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("term,source\n".utf8).write(to: url)

        viewModel.importEntries(from: url)

        #expect(viewModel.allWords.isEmpty)
        #expect(viewModel.importAlert == .failure(DictionaryImportError.empty.localizedDescription))
    }
}
