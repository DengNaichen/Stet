import Foundation
import Combine
import StetCore

@MainActor
final class DictionaryViewModel: ObservableObject {
    private let model: DictionaryModel
    private var syncObserver: NSObjectProtocol?

    @Published private(set) var allWords: [String] = []
    @Published var draft = ""

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

    func addDraftEntries() {
        guard canAddDraftEntries else { return }
        allWords = model.addEntries(from: draft)
        draft = ""
    }

    func removeWord(_ word: String) {
        allWords = model.removeEntry(word)
    }
}
