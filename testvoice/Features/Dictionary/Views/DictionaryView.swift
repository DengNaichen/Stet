import SwiftUI

struct DictionaryView: View {
    @StateObject private var viewModel = DictionaryViewModel()
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 0) {
                    List {
                        ForEach(viewModel.allWords, id: \.self) { word in
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



#Preview {
    DictionaryView()
}
