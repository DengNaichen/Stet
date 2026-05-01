import Foundation
import Combine

@MainActor
final class DictionaryViewModel: ObservableObject {
    @Published private(set) var allWords: [String] = ["Swift test", "document.go", "triggle", "GPT", "rhythm", "AirType", "CTO", "Soul"]
    
    func addNewWord() {
        // Logic to add a new word
        print("Opening add word dialog...")
    }
}
