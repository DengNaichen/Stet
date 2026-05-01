import Foundation
import Combine

@MainActor
final class HomeViewModel: ObservableObject {
    @Published private(set) var totalHours: String = "12"
    @Published private(set) var totalMinutes: String = "58"
    @Published private(set) var wordsDictated: String = "100.6K"
    @Published private(set) var timeSaved: String = "49"
    @Published private(set) var averageWPM: String = "194"
    
    @Published var currentWords: Double = 6531
    @Published var totalWordsLimit: Double = 8000
    
    var progress: Double {
        currentWords / totalWordsLimit
    }
    
    func upgradeToPro() {
        // Logic for handling upgrade
        print("Redirecting to upgrade page...")
    }
}
