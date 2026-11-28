import Combine
import Foundation
import StetCore

@MainActor
final class DictionaryViewModel: ObservableObject {
    enum ImportAlert: Equatable, Identifiable {
        case success(added: Int, skipped: Int)
        case failure(String)

        var id: String {
            switch self {
            case .success(let added, let skipped):
                return "success-\(added)-\(skipped)"
            case .failure(let message):
                return "failure-\(message)"
            }
        }

        var title: String { "Import Dictionary" }

        var message: String {
            switch self {
            case .success(let added, let skipped) where skipped == 0:
                return "Added \(added) terms."
            case .success(let added, let skipped):
                return "Added \(added), skipped \(skipped) duplicates."
            case .failure(let message):
                return message
            }
        }
    }

    private let model: DictionaryModel
    private var syncObserver: NSObjectProtocol?

    @Published private(set) var allWords: [String] = []
    @Published var draft = ""
    @Published var importAlert: ImportAlert?

    init(model: DictionaryModel = DictionaryModel()) {
        self.model = model
        self.syncObserver = NotificationCenter.default.addObserver(
            forName: .dictionaryDidSync,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [self] in self.load() }
        }
    }

    var canAddDraftEntries: Bool {
        !DictionaryModel.words(from: draft).isEmpty
    }

    func load() {
        allWords = model.loadEntries()
    }

    func refreshFromCloud() {
        NSUbiquitousKeyValueStore.default.synchronize()
        load()
    }

    func addDraftEntries() {
        guard canAddDraftEntries else { return }
        allWords = model.addEntries(from: draft)
        draft = ""
    }

    func removeWord(_ word: String) {
        allWords = model.removeEntry(word)
    }

    func exportCSVData() -> Data {
        model.exportCSVData()
    }

    func importEntries(from url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }
        do {
            let data = try Data(contentsOf: url)
            let text = try DictionaryModel.importText(from: data)
            let format = DictionaryImportFormat.inferred(from: url)
            let result = try model.importEntries(from: text, format: format)
            allWords = model.loadEntries()
            importAlert = .success(added: result.addedCount, skipped: result.skippedCount)
        } catch let error as DictionaryImportError {
            importAlert = .failure(error.localizedDescription)
        } catch {
            importAlert = .failure(error.localizedDescription)
        }
    }
}
