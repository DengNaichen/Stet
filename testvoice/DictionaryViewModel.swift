import Foundation
import Combine

enum DictionaryFilter: String, CaseIterable {
    case all = "All"
    case auto = "Auto-added"
    case manual = "Manually-added"
}

@MainActor
final class DictionaryViewModel: ObservableObject {
    @Published var selectedFilter: DictionaryFilter = .all
    @Published private(set) var allWords: [String] = ["Swift test", "document.go", "triggle", "GPT", "rhythm", "AirType", "CTO", "Soul"]
    
    var filteredWords: [String] {
        // In a real app, you'd filter by the selectedFilter type
        allWords
    }
    
    func addNewWord() {
        // Logic to add a new word
        print("Opening add word dialog...")
    }
}
