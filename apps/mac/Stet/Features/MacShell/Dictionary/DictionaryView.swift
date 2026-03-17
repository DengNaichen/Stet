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
            } header: {
                Text("Personal Dictionary")
            } footer: {
                Text(
                    viewModel.isEnabled
                        ? "When enabled, saved entries are used during transcription and rewrite."
                        : "When disabled, saved entries stay on this Mac but are ignored during transcription and rewrite."
                )
            }

            Section {
                if viewModel.entries.isEmpty {
                    Text("Once you add words here, Stet will reuse them in OpenAI transcription and rewrite.")
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
                }
            } header: {
                Text("Current Entries")
            } footer: {
                Text("Separate multiple entries with commas. These terms are stored locally on this Mac.")
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 20)
        .padding(.bottom, 28)
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
}
#endif
