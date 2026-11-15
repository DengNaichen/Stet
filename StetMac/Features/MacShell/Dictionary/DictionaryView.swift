#if os(macOS)
    import StetCore
    import SwiftUI
    import UniformTypeIdentifiers

    struct DictionaryView: View {
        @ObservedObject var viewModel: DictionaryViewModel

        private let dictionaryColumns = [
            GridItem(
                .adaptive(minimum: MacUI.DictionaryViewMetrics.gridMinColumnWidth),
                spacing: MacUI.DictionaryViewMetrics.gridSpacing,
                alignment: .leading
            )
        ]

        @State private var isShowingClearConfirmation = false
        @State private var isShowingEditor = false
        @State private var editingEntry: String?
        @State private var entryDraft = ""
        @State private var clearConfirmation = ""
        @State private var isImportingFile = false

        private var entryDraftBinding: Binding<String> {
            Binding(
                get: { entryDraft },
                set: { value in
                    let singleLine = value.components(separatedBy: .newlines)
                        .filter { !$0.isEmpty }
                        .joined(separator: ", ")
                    entryDraft = String(singleLine.prefix(200))
                }
            )
        }

        private var isEnabledBinding: Binding<Bool> {
            Binding(
                get: { viewModel.isEnabled },
                set: { viewModel.setEnabled($0) }
            )
        }

        var body: some View {
            LinearPageContainer(
                title: "Dictionary",
                preservesExpandedToolbar: false
            ) {
                LinearSectionGroup("Personal Dictionary") {
                    LinearSettingRow(
                        "Enable Personal Dictionary",
                        subtitle: "Help Stet recognize names, brands, and phrases in your transcripts and rewrites."
                    ) {
                        Toggle("", isOn: isEnabledBinding)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .tint(MacUI.LinearBrand.accent)
                    }
                }

                LinearSectionGroup("Current Entries") {
                    HStack {
                        Text("\(viewModel.entries.count) words and phrases")
                            .font(MacUI.LinearTypography.rowSubtitle)
                            .foregroundStyle(MacUI.Foreground.secondary)
                        Spacer()
                        if !viewModel.entries.isEmpty {
                            Button("Clear Dictionary", role: .destructive) {
                                clearConfirmation = ""
                                isShowingClearConfirmation = true
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.horizontal, MacUI.LinearMetrics.rowHorizontalPadding)
                    .padding(.top, 10)
                    .padding(.bottom, 6)

                    if viewModel.entries.isEmpty {
                        Text("Once you add words here, Stet will reuse them in transcription and rewrite.")
                            .font(MacUI.LinearTypography.rowSubtitle)
                            .foregroundStyle(MacUI.Foreground.secondary)
                            .padding(.horizontal, MacUI.LinearMetrics.rowHorizontalPadding)
                            .padding(.vertical, 14)
                    } else {
                        LazyVGrid(
                            columns: dictionaryColumns,
                            alignment: .leading,
                            spacing: MacUI.DictionaryViewMetrics.gridSpacing
                        ) {
                            ForEach(viewModel.entries, id: \.self) { entry in
                                dictionaryChip(for: entry)
                            }
                        }
                        .padding(MacUI.LinearMetrics.rowHorizontalPadding)
                    }
                }
            }
            .macSettingsSheet(isPresented: $isShowingEditor) {
                MacSettingsEditor(
                    title: editingEntry == nil ? "Add Dictionary Words" : "Edit Dictionary Entry",
                    subtitle:
                        "Use the spelling you want in your transcripts. Separate words or phrases with commas. Up to 200 characters."
                ) {
                    Text("Words or phrases").font(MacUI.LinearTypography.rowTitle)
                    TextField("Words or phrases", text: entryDraftBinding, axis: .horizontal)
                        .font(.system(size: 13))
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1)
                        .labelsHidden()
                        .accessibilityLabel("Words or phrases")
                    HStack {
                        Spacer()
                        Button("Cancel") { isShowingEditor = false }
                            .buttonStyle(.bordered)
                            .keyboardShortcut(.cancelAction)
                        Button(editingEntry == nil ? "Add Words" : "Save") {
                            viewModel.saveEntries(from: entryDraft, replacing: editingEntry)
                            isShowingEditor = false
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!viewModel.canSaveEntries(from: entryDraft))
                    }
                }
            }
            .macSettingsSheet(isPresented: $isShowingClearConfirmation) {
                MacSettingsEditor(
                    title: "Clear Personal Dictionary?",
                    subtitle:
                        "This permanently removes all \(viewModel.entries.count) entries, including on devices using your synced dictionary. This cannot be undone."
                ) {
                    Text("Type CLEAR to confirm.").font(MacUI.LinearTypography.rowTitle)
                    TextField("CLEAR", text: $clearConfirmation)
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                    HStack {
                        Spacer()
                        Button("Cancel") { isShowingClearConfirmation = false }
                            .buttonStyle(.bordered)
                            .keyboardShortcut(.cancelAction)
                        Button("Clear Dictionary", role: .destructive) {
                            viewModel.clearEntries()
                            isShowingClearConfirmation = false
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(clearConfirmation != "CLEAR")
                    }
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        isImportingFile = true
                    } label: {
                        Label("Import…", systemImage: "square.and.arrow.down")
                    }
                    .help("Import words or phrases from a file")

                    Button {
                        openEditor()
                    } label: {
                        Label("Add Words…", systemImage: "plus")
                    }
                    .help("Add words or phrases")
                }
            }
            .onAppear { viewModel.load() }
            .fileImporter(
                isPresented: $isImportingFile,
                allowedContentTypes: [.plainText, .commaSeparatedText, .utf8PlainText],
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
        }

        private func openEditor(_ entry: String? = nil) {
            editingEntry = entry
            entryDraft = entry ?? ""
            isShowingEditor = true
        }

        private func dictionaryChip(for entry: String) -> some View {
            let isAutomatic = viewModel.source(for: entry) == .automatic
            return HStack(spacing: MacUI.DictionaryViewMetrics.chipSpacing) {
                Button {
                    openEditor(entry)
                } label: {
                    Text(entry)
                        .font(MacUI.DictionaryViewMetrics.chipTextFont)
                        .foregroundStyle(MacUI.Foreground.primary)
                        .lineLimit(MacUI.DictionaryViewMetrics.entryLineLimit)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .help("Edit entry")

                Image(systemName: isAutomatic ? "sparkles" : "person")
                    .font(.system(size: 10))
                    .foregroundStyle(MacUI.LinearSurfaces.mutedInk)
                    .help(isAutomatic ? Text("Automatically learned") : Text("Manually added"))
                    .accessibilityLabel(isAutomatic ? Text("Automatically learned") : Text("Manually added"))

                Button {
                    viewModel.removeEntry(entry)
                } label: {
                    Image(systemName: "xmark")
                        .font(MacUI.DictionaryViewMetrics.chipButtonIconFont)
                        .foregroundStyle(MacUI.LinearSurfaces.mutedInk)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(entry)")
            }
            .padding(.horizontal, MacUI.DictionaryViewMetrics.chipHorizontalPadding)
            .padding(.vertical, MacUI.DictionaryViewMetrics.chipVerticalPadding)
            .background(
                RoundedRectangle(cornerRadius: MacUI.DictionaryViewMetrics.chipCornerRadius, style: .continuous)
                    .fill(MacUI.LinearSurfaces.elevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: MacUI.DictionaryViewMetrics.chipCornerRadius, style: .continuous)
                    .strokeBorder(MacUI.LinearSurfaces.hairline, lineWidth: 1)
            )
        }
    }
#endif
