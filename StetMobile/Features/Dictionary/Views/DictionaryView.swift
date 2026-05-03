import SwiftUI

struct DictionaryView: View {
    @StateObject private var viewModel = DictionaryViewModel()
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    TextField("Add words or phrases", text: $viewModel.draft, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .focused($isTextFieldFocused)
                        .onSubmit {
                            viewModel.addDraftEntries()
                        }

                    Button("Add") {
                        viewModel.addDraftEntries()
                        isTextFieldFocused = false
                    }
                    .disabled(!viewModel.canAddDraftEntries)
                }

                List {
                    if viewModel.allWords.isEmpty {
                        Text("Words you add here will be reused during dictation and rewrite.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.allWords, id: \.self) { word in
                            HStack(spacing: 12) {
                                Image(systemName: "sparkles")
                                    .foregroundStyle(Color(red: 0.4, green: 0.8, blue: 0.7))
                                Text(word)
                                Spacer()
                                Button(role: .destructive) {
                                    viewModel.removeWord(word)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Dictionary")
            .padding()
            .onAppear {
                viewModel.load()
            }
        }
    }
}

#Preview {
    DictionaryView()
}
