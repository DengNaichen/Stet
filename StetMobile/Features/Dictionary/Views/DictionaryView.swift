import SwiftUI

struct DictionaryView: View {
    @StateObject private var viewModel = DictionaryViewModel()
    @FocusState private var isTextFieldFocused: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        NavigationStack {
            List {
                Section {
                    entryLayout {
                        TextField("Add words or phrases", text: $viewModel.draft, axis: .vertical)
                            .lineLimit(1...3)
                            .textFieldStyle(.plain)
                            .focused($isTextFieldFocused)
                            .submitLabel(.done)
                            .onSubmit {
                                addDraftEntries()
                            }

                        Button("Add") {
                            addDraftEntries()
                        }
                        .buttonStyle(.borderless)
                        .disabled(!viewModel.canAddDraftEntries)
                        .frame(maxWidth: addButtonMaxWidth, alignment: .trailing)
                    }
                }

                if viewModel.allWords.isEmpty {
                    ContentUnavailableView {
                        Label("No Words Yet", systemImage: "text.badge.plus")
                    } description: {
                        Text("Words you add here will be reused during dictation and rewrite.")
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else {
                    Section("Words and Phrases") {
                        ForEach(viewModel.allWords, id: \.self) { word in
                            HStack {
                                Text(word)
                                Spacer()
                                Button(role: .destructive) {
                                    viewModel.removeWord(word)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Delete \(word)")
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Dictionary")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                viewModel.load()
            }
        }
    }

    private var entryLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
    }

    private var addButtonMaxWidth: CGFloat? {
        dynamicTypeSize.isAccessibilitySize ? .infinity : nil
    }

    private func addDraftEntries() {
        viewModel.addDraftEntries()
        isTextFieldFocused = false
    }
}

#Preview {
    DictionaryView()
}
