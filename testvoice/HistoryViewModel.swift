import Foundation
import Combine

struct HistoryRecord: Identifiable {
    let id = UUID()
    let title: String
    let date: String
    let duration: String
}

@MainActor
final class HistoryViewModel: ObservableObject {
    @Published var records: [HistoryRecord] = []
    @Published var keepHistorySetting: String = "Never"
    
    init() {
        fetchRecords()
    }
    
    func fetchRecords() {
        // Dummy data for now
        self.records = [
            HistoryRecord(title: "Project Brainstorming", date: "Today, 10:30 AM", duration: "12:45"),
            HistoryRecord(title: "Grocery Shopping List", date: "Yesterday, 6:15 PM", duration: "01:30"),
            HistoryRecord(title: "Meeting Notes - Q2 Review", date: "April 28, 2024", duration: "45:20"),
            HistoryRecord(title: "Journal Entry", date: "April 27, 2024", duration: "05:10"),
            HistoryRecord(title: "App Idea - Voice Notes", date: "April 25, 2024", duration: "03:15")
        ]
    }
}
