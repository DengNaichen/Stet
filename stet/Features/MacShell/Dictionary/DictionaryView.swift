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

                    LabeledContent("Entries") {
                        MacSettingsStatusBadge(
                            text: "\(viewModel.entries.count)",
                            tint: viewModel.isEnabled && !viewModel.entries.isEmpty
                                ? .accentColor : .gray
                        )
                    }

                    HStack(alignment: .firstTextBaseline, spacing: MacUI.DictionaryViewMetrics.entryInputSpacing) {
                        TextField(
                            "Add names, brands, jargon, or phrases",
                            text: $viewModel.draft
                        )
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            viewModel.addDraftEntries()
                        }

                        Button("Add") {
                            viewModel.addDraftEntries()
                        }
                        .disabled(!viewModel.canAddDraftEntries)
                    }
                } header: {
                    Text("Personal Dictionary")
                }

                Section {
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
                            viewModel.clearEntries()
                        }
                    }
                } header: {
                    Text("Current Entries")
                }
            }
            .formStyle(.grouped)
            .padding(.horizontal, MacUI.SettingsViewMetrics.formHorizontalPadding)
            .padding(.bottom, MacUI.SettingsViewMetrics.formBottomPadding)
        }

        private func dictionaryChip(for entry: String) -> some View {
            HStack(spacing: MacUI.DictionaryViewMetrics.chipSpacing) {
                Text(entry)
                    .font(MacUI.DictionaryViewMetrics.chipTextFont)
                    .lineLimit(MacUI.DictionaryViewMetrics.entryLineLimit)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    viewModel.removeEntry(entry)
                } label: {
                    Image(systemName: "xmark")
                        .font(MacUI.DictionaryViewMetrics.chipButtonIconFont)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
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
