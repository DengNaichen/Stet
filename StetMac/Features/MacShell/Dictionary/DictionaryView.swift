#if os(macOS)
    import SwiftUI

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

        private var isEnabledBinding: Binding<Bool> {
            Binding(
                get: { viewModel.isEnabled },
                set: { viewModel.setEnabled($0) }
            )
        }

        var body: some View {
            Form {
                Section {
                    Toggle("Enable Personal Dictionary", isOn: isEnabledBinding)

                    Text("Help Stet recognize names, brands, and phrases in your transcripts and rewrites.")
                        .font(.callout).foregroundStyle(.secondary)
                } header: {
                    Text("Personal Dictionary")
                }

                Section {
                    HStack {
                        Text("\(viewModel.entries.count) words and phrases").foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            openEditor()
                        } label: {
                            Label("Add Words…", systemImage: "plus")
                        }
                    }
                    if viewModel.entries.isEmpty {
                        Text("Once you add words here, Stet will reuse them in transcription and rewrite.")
                            .foregroundStyle(.secondary)
                    } else {
                        LazyVGrid(
                            columns: dictionaryColumns, alignment: .leading,
                            spacing: MacUI.DictionaryViewMetrics.gridSpacing
                        ) {
                            ForEach(viewModel.entries, id: \.self) { entry in
                                dictionaryChip(for: entry)
                            }
                        }

                        Button("Clear Dictionary", role: .destructive) {
                            clearConfirmation = ""
                            isShowingClearConfirmation = true
                        }
                        .foregroundStyle(.red)
                    }
                } header: {
                    Text("Current Entries")
                }
            }
            .macSettingsFormStyle()
            .padding(.bottom, MacUI.SettingsViewMetrics.formBottomPadding)
            .macSettingsSheet(isPresented: $isShowingEditor) {
                MacSettingsEditor(
                    title: editingEntry == nil ? "Add Dictionary Words" : "Edit Dictionary Entry",
                    subtitle:
                        "Use the spelling you want in your transcripts. Separate multiple words or phrases with commas or new lines."
                ) {
                    Text("Words or phrases").font(.subheadline)
                    TextEditor(text: $entryDraft)
                        .font(.body)
                        .frame(height: 110)
                        .padding(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: MacUI.SettingsViewMetrics.sidebarRowCornerRadius)
                                .strokeBorder(Color.secondary.opacity(0.25))
                        )
                        .accessibilityLabel("Words or phrases")
                    HStack {
                        Spacer()
                        Button("Cancel") { isShowingEditor = false }.keyboardShortcut(.cancelAction)
                        Button(editingEntry == nil ? "Add Words" : "Save") {
                            viewModel.saveEntries(from: entryDraft, replacing: editingEntry)
                            isShowingEditor = false
                        }
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
                    Text("Type CLEAR to confirm.").font(.subheadline)
                    TextField("CLEAR", text: $clearConfirmation).textFieldStyle(.roundedBorder).labelsHidden()
                    HStack {
                        Spacer()
                        Button("Cancel") { isShowingClearConfirmation = false }.keyboardShortcut(.cancelAction)
                        Button("Clear Dictionary", role: .destructive) {
                            viewModel.clearEntries()
                            isShowingClearConfirmation = false
                        }
                        .disabled(clearConfirmation != "CLEAR")
                    }
                }
            }
            .onAppear { viewModel.load() }
        }

        private func openEditor(_ entry: String? = nil) {
            editingEntry = entry
            entryDraft = entry ?? ""
            isShowingEditor = true
        }

        private func dictionaryChip(for entry: String) -> some View {
            HStack(spacing: MacUI.DictionaryViewMetrics.chipSpacing) {
                Button {
                    openEditor(entry)
                } label: {
                    Text(entry)
                        .font(MacUI.DictionaryViewMetrics.chipTextFont)
                        .lineLimit(MacUI.DictionaryViewMetrics.entryLineLimit)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)

                }
                .buttonStyle(.plain)
                .help("Edit entry")

                Button {
                    viewModel.removeEntry(entry)
                } label: {
                    Image(systemName: "xmark")
                        .font(MacUI.DictionaryViewMetrics.chipButtonIconFont)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(entry)")
            }
            .padding(.horizontal, MacUI.DictionaryViewMetrics.chipHorizontalPadding)
            .padding(.vertical, MacUI.DictionaryViewMetrics.chipVerticalPadding)
            .background(
                RoundedRectangle(cornerRadius: MacUI.DictionaryViewMetrics.chipCornerRadius, style: .continuous)
                    .fill(Color.secondary.opacity(MacUI.DictionaryViewMetrics.chipFillOpacity))
            )
            .overlay(
                RoundedRectangle(cornerRadius: MacUI.DictionaryViewMetrics.chipCornerRadius, style: .continuous)
                    .strokeBorder(
                        Color.primary.opacity(MacUI.DictionaryViewMetrics.chipStrokeOpacity),
                        lineWidth: MacUI.DictionaryViewMetrics.chipStrokeLineWidth)
            )
        }
    }
#endif
