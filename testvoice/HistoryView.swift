import SwiftUI

struct HistoryItem: Identifiable {
    let id = UUID()
    let title: String
    let date: String
    let duration: String
}

struct HistoryView: View {
    @StateObject private var viewModel = HistoryViewModel()
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Image(systemName: "archivebox")
                            .foregroundStyle(.secondary)
                        Text("Keep history")
                        Spacer()
                        Text(viewModel.keepHistorySetting)
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "lock.shield")
                                .foregroundStyle(.black)
                            Text("Your data stays private")
                                .fontWeight(.semibold)
                        }
                        
                        Text("Your voice dictations are private with zero data retention. They are stored only on your device and cannot be accessed from anywhere else.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineSpacing(4)
                    }
                    .padding(.vertical, 8)
                }
                
                Section("Recent Dictations") {
                    ForEach(viewModel.records) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title)
                                    .fontWeight(.medium)
                                Text(item.date)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(item.duration)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color(.systemGray6))
                                .cornerRadius(8)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("History")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {}) {
                        Image(systemName: "ellipsis")
                            .rotationEffect(.degrees(90))
                    }
                }
            }
        }
    }
}

#Preview {
    HistoryView()
}
