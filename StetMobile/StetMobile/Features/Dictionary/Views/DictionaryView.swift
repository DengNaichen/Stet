import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct DictionaryView: View {
    @StateObject private var viewModel = DictionaryViewModel()
    @FocusState private var isTextFieldFocused: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @State private var isImportingFile = false
    @State private var isExportingFile = false
    @State private var exportDocument = DictionaryCSVDocument()

    private static let recommendedHotwordLimit = 100

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(viewModel.allWords.count) / \(Self.recommendedHotwordLimit) Hotwords")
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                .foregroundStyle(.primary)

                            Spacer()

                            Text("iCloud Sync")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.tertiary)
                        }

                        GeometryReader { proxy in
                            let ratio = min(
                                1,
                                CGFloat(viewModel.allWords.count) / CGFloat(Self.recommendedHotwordLimit)
                            )
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.primary.opacity(0.08))
                                Capsule()
                                    .fill(MobileLinearPalette.accentAmber)
                                    .frame(width: max(ratio > 0 ? 4 : 0, proxy.size.width * ratio))
                            }
                        }
                        .frame(height: 3)

                        Text("Guides Apple Speech on-device and Cloud AI Rewrite across Mac and iPhone.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
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
                            Text("Add")
                                .font(.subheadline.weight(.medium))
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .controlSize(.small)
                        .tint(.primary)
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
                            Text(word)
                                .font(.body)
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
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
            .linearInlineHeader("Dictionary")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            isImportingFile = true
                        } label: {
                            Label("Import CSV / TXT…", systemImage: "square.and.arrow.down")
                        }

                        Button {
                            exportDocument = DictionaryCSVDocument(data: viewModel.exportCSVData())
                            isExportingFile = true
                        } label: {
                            Label("Export CSV…", systemImage: "square.and.arrow.up")
                        }
                        .disabled(viewModel.allWords.isEmpty)
                    } label: {
                        Image(systemName: "ellipsis")
                            .accessibilityLabel("Dictionary actions")
                    }
                }
            }
            .fileImporter(
                isPresented: $isImportingFile,
                allowedContentTypes: [.commaSeparatedText, .plainText, .utf8PlainText],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    viewModel.importEntries(from: url)
                case .failure(let error):
                    viewModel.importAlert = .failure(error.localizedDescription)
                }
            }
            .fileExporter(
                isPresented: $isExportingFile,
                document: exportDocument,
                contentType: .commaSeparatedText,
                defaultFilename: "stet-dictionary.csv"
            ) { result in
                if case .failure(let error) = result {
                    viewModel.importAlert = .failure(error.localizedDescription)
                }
            }
            .alert(
                viewModel.importAlert?.title ?? "Import Dictionary",
                isPresented: Binding(
                    get: { viewModel.importAlert != nil },
                    set: { if !$0 { viewModel.importAlert = nil } }
                ),
                presenting: viewModel.importAlert
            ) { _ in
                Button("OK") { viewModel.importAlert = nil }
            } message: { alert in
                Text(alert.message)
            }
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

    private func addDraftEntries() {
        withAnimation(.spring(response: 0.3, dampingFraction: 1.0)) {
            viewModel.addDraftEntries()
        }
        isTextFieldFocused = false
    }
}

private struct DictionaryCSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }

    var data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

#Preview {
    DictionaryView()
}
