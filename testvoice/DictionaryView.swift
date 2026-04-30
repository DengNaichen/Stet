import SwiftUI

struct DictionaryView: View {
    @StateObject private var viewModel = DictionaryViewModel()
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 0) {
                    // Segmented Picker
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(DictionaryFilter.allCases, id: \.self) { filter in
                                PickerItem(title: filter.rawValue, 
                                           icon: filter == .auto ? "sparkles" : (filter == .manual ? "feather" : nil),
                                           isSelected: viewModel.selectedFilter == filter)
                                    .onTapGesture { viewModel.selectedFilter = filter }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 12)
                    }
                    
                    List {
                        ForEach(viewModel.filteredWords, id: \.self) { word in
                            HStack(spacing: 16) {
                                Image(systemName: "sparkles")
                                    .foregroundStyle(Color(red: 0.4, green: 0.8, blue: 0.7)) // Mint green
                                Text(word)
                                    .fontWeight(.medium)
                            }
                            .padding(.vertical, 8)
                        }
                    }
                    .listStyle(.plain)
                }
                
                // FAB
                Button(action: viewModel.addNewWord) {
                    Image(systemName: "plus")
                        .font(.title2.bold())
                        .foregroundColor(.white)
                        .frame(width: 56, height: 56)
                        .background(Color.black.opacity(0.9))
                        .clipShape(Circle())
                        .shadow(radius: 4)
                }
                .padding(24)
            }
            .navigationTitle("Dictionary")
        }
    }
}

struct PickerItem: View {
    let title: String
    var icon: String? = nil
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 6) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.caption)
            }
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(isSelected ? Color(.systemGray5) : Color(.systemGray6))
        .foregroundColor(isSelected ? .black : .secondary)
        .clipShape(Capsule())
    }
}

#Preview {
    DictionaryView()
}
