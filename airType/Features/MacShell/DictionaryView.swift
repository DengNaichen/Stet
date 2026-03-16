#if os(macOS)
    import SwiftUI

    struct DictionaryView: View {
        @ObservedObject var viewModel: DictionaryViewModel

        private let dictionaryColumns = [
            GridItem(.adaptive(minimum: 180), spacing: 8, alignment: .leading)
        ]

        private var isEnabledBinding: Binding<Bool> {
            Binding(
                get: { viewModel.isEnabled },
                set: { viewModel.setEnabled($0) }
            )
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                settingsCard(
                    title: "Personal Dictionary",
                    description:
                        "Add exact spellings for names, brands, jargon, and phrases you want OpenAI transcription and rewrite to preserve."
                ) {
                    Toggle("Enable Personal Dictionary", isOn: isEnabledBinding)

                    Text(
                        viewModel.isEnabled
                            ? "When enabled, saved entries are used during transcription and rewrite."
                            : "When disabled, saved entries stay on this Mac but are ignored during transcription and rewrite."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    settingsValueRow(title: "Entries") {
                        statusBadge(
                            "\(viewModel.entries.count)",
                            tint: viewModel.isEnabled && !viewModel.entries.isEmpty
                                ? .accentColor : .gray
                        )
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 10) {
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

                    Text(
                        "Separate multiple entries with commas. These terms are stored locally on this Mac."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                settingsCard(
                    title: "Current Entries",
                    description: viewModel.entries.isEmpty ? "Your dictionary is empty." : nil
                ) {
                    if viewModel.entries.isEmpty {
                        Text(
                            "Once you add words here, airType will reuse them in OpenAI transcription and rewrite."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    } else {
                        LazyVGrid(columns: dictionaryColumns, alignment: .leading, spacing: 8) {
                            ForEach(viewModel.entries, id: \.self) { entry in
                                dictionaryChip(for: entry)
                            }
                        }

                        Button("Clear Dictionary", role: .destructive) {
                            viewModel.clearEntries()
                        }
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
            }
        }

        private func dictionaryChip(for entry: String) -> some View {
            HStack(spacing: 8) {
                Text(entry)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    viewModel.removeEntry(entry)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.secondary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            )
        }

        private func settingsCard<Content: View>(
            title: String,
            description: String? = nil,
            @ViewBuilder content: () -> Content
        ) -> some View {
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text(title)
                        .font(.headline)

                    if let description {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    content()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }
        }

        @ViewBuilder
        private func settingsValueRow<Value: View>(
            title: String,
            @ViewBuilder value: () -> Value
        ) -> some View {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(title)
                    .foregroundStyle(.secondary)
                Spacer()
                value()
            }
        }

        private func statusBadge(_ text: String, tint: Color) -> some View {
            Text(text)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule(style: .continuous)
                        .fill(tint.opacity(0.12))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(tint.opacity(0.22), lineWidth: 1)
                )
        }
    }
#endif
