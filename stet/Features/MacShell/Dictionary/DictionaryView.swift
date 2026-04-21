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


                    VStack(alignment: .leading, spacing: 8) {
                        Text("Add names, brands, jargon, or phrases")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        HStack(spacing: MacUI.DictionaryViewMetrics.entryInputSpacing) {
                            TextField(
                                "",
                                text: $viewModel.draft
                            )
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.leading)
                            .labelsHidden()
                            .onSubmit {
                                viewModel.addDraftEntries()
                            }

                            Button("Add") {
                                viewModel.addDraftEntries()
                            }
                            .disabled(!viewModel.canAddDraftEntries)
                        }
                    }
                    .padding(.vertical, 4)
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
                            isShowingClearConfirmation = true
                        }
                        .foregroundStyle(.red)
                    }
                } header: {
                    Text("Current Entries")
                }
            }
            .formStyle(.grouped)
            .padding(.leading, MacUI.SettingsViewMetrics.formHorizontalPadding)
            .padding(.bottom, MacUI.SettingsViewMetrics.formBottomPadding)
            .confirmationDialog(
                "Are you sure you want to clear your personal dictionary?",
                isPresented: $isShowingClearConfirmation,
                titleVisibility: .visible
            ) {
                Button("Clear All", role: .destructive) {
                    viewModel.clearEntries()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This action cannot be undone.")
            }
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
