import SwiftUI
import UIKit

struct DictionaryView: View {
    @StateObject private var viewModel = DictionaryViewModel()
    @FocusState private var isTextFieldFocused: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase

    private static let recommendedHotwordLimit = 100

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "text.book.closed.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(
                                Color.indigo.gradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(viewModel.allWords.count) / \(Self.recommendedHotwordLimit) Hotwords")
                                .font(.subheadline.weight(.semibold))
                            Text("Guides Apple Speech on-device and Cloud AI Rewrite.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Label("Synced via iCloud across Mac and iPhone.", systemImage: "icloud")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .padding(.top, 2)
                        }
                    }
                    .padding(.vertical, 2)
                }

                Section {
                    entryLayout {
                        TextField("Add names, jargon, or phrases…", text: $viewModel.draft, axis: .vertical)
                            .lineLimit(1...3)
                            .textFieldStyle(.plain)
                            .focused($isTextFieldFocused)
                            .submitLabel(.done)
                            .onSubmit {
                                addDraftEntries()
                            }

                        Button {
                            addDraftEntries()
                        } label: {
                            Label("Add", systemImage: "plus")
                                .font(.subheadline.weight(.semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                        .controlSize(.small)
                        .disabled(!viewModel.canAddDraftEntries)
                        .frame(maxWidth: addButtonMaxWidth, alignment: .trailing)
                    }
                    .padding(.vertical, 2)
                } footer: {
                    Text("Separate multiple terms with commas or new lines.")
                }

                if viewModel.allWords.isEmpty {
                    ContentUnavailableView {
                        Label("No Personal Words Yet", systemImage: "text.badge.plus")
                    } description: {
                        Text(
                            "Add product names, people, or technical terms so Stet recognizes and spells them accurately."
                        )
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .padding(.vertical, 24)
                } else {
                    Section {
                        ForEach(viewModel.allWords, id: \.self) { word in
                            HStack(spacing: 12) {
                                Text(monogram(for: word))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 28, height: 28)
                                    .background(Color(.tertiarySystemFill), in: Circle())

                                Text(word)
                                    .font(.body)
                                    .foregroundStyle(.primary)

                                Spacer()
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    withAnimation {
                                        viewModel.removeWord(word)
                                    }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .contextMenu {
                                Button {
                                    UIPasteboard.general.string = word
                                } label: {
                                    Label("Copy", systemImage: "doc.on.doc")
                                }
                                Button(role: .destructive) {
                                    viewModel.removeWord(word)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    } header: {
                        Text("Saved Words")
                    } footer: {
                        Text("Swipe left on any word to remove it.")
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
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    viewModel.refreshFromCloud()
                }
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

    private func monogram(for word: String) -> String {
        guard let first = word.trimmingCharacters(in: .whitespacesAndNewlines).first else {
            return "#"
        }
        return String(first).uppercased()
    }

    private func addDraftEntries() {
        withAnimation(.spring(response: 0.3, dampingFraction: 1.0)) {
            viewModel.addDraftEntries()
        }
        isTextFieldFocused = false
    }
}

#Preview {
    DictionaryView()
}
