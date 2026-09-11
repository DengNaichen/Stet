#if os(macOS)
    import AppKit
    import StetCore
    import SwiftUI
    import UniformTypeIdentifiers

    struct MacHistorySettingsView: View {
        @Environment(\.scenePhase) private var scenePhase
        @State private var entries: [HistoryEntry] = []
        @State private var searchText = ""
        @State private var isExporting = false
        @State private var showDeleteConfirmation = false
        @State private var loadError: String?

        private var filtered: [HistoryEntry] {
            guard !searchText.isEmpty else { return entries }
            let q = searchText.lowercased()
            return entries.filter {
                ($0.rawText.lowercased().contains(q))
                    || ($0.llmText?.lowercased().contains(q) == true)
                    || ($0.targetAppName?.lowercased().contains(q) == true)
                    || ($0.targetBundleID?.lowercased().contains(q) == true)
            }
        }

        var body: some View {
            VStack(spacing: 0) {
                toolbar
                Divider()
                content
            }
            .task { reload() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { reload() } }
        }

        // MARK: - Toolbar

        private var toolbar: some View {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tertiary)
                    .imageScale(.small)
                TextField(LocalizedStringKey("Search History"), text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .imageScale(.small)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Button {
                    reload()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh history").accessibilityLabel("Refresh history")
                Button(LocalizedStringKey("Export JSON")) {
                    exportJSON()
                }
                .disabled(entries.isEmpty)
                Button(LocalizedStringKey("Clear All"), role: .destructive) {
                    showDeleteConfirmation = true
                }
                .disabled(entries.isEmpty)
                .confirmationDialog(
                    LocalizedStringKey("Clear all history?"),
                    isPresented: $showDeleteConfirmation,
                    titleVisibility: .visible
                ) {
                    Button(LocalizedStringKey("Clear All"), role: .destructive) {
                        deleteAll()
                    }
                } message: {
                    Text(LocalizedStringKey("This action cannot be undone."))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }

        // MARK: - Content

        @ViewBuilder
        private var content: some View {
            if let loadError {
                ContentUnavailableView(
                    LocalizedStringKey("Could not load history"),
                    systemImage: "exclamationmark.triangle",
                    description: Text(loadError)
                )
            } else if filtered.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? LocalizedStringKey("No History") : LocalizedStringKey("No Results"),
                    systemImage: searchText.isEmpty ? "clock" : "magnifyingglass",
                    description: Text(
                        searchText.isEmpty
                            ? LocalizedStringKey("Dictation sessions will appear here.")
                            : LocalizedStringKey("Try a different search term.")
                    )
                )
            } else {
                List(filtered, id: \.id) { entry in
                    HistoryEntryRow(entry: entry)
                        .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
                }
                .listStyle(.plain)
                .macSettingsTracksTitleScroll()
            }
        }

        // MARK: - Actions

        private func reload() {
            do {
                entries = try DictationHistoryService.shared.fetchRecent()
                loadError = nil
            } catch {
                loadError = error.localizedDescription
            }
        }

        private func deleteAll() {
            do {
                try DictationHistoryService.shared.deleteAll()
                entries = []
            } catch {
                loadError = error.localizedDescription
            }
        }

        private func exportJSON() {
            let snapshot = entries.map { HistoryEntry.ExportRepresentation(from: $0) }
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            guard let data = try? encoder.encode(snapshot) else { return }

            let panel = NSSavePanel()
            panel.nameFieldStringValue = "stet-history.json"
            panel.allowedContentTypes = [.json]
            panel.canCreateDirectories = true
            panel.begin { response in
                guard response == .OK, let url = panel.url else { return }
                try? data.write(to: url)
            }
        }
    }

    // MARK: - HistoryEntryRow

    private struct HistoryEntryRow: View {
        let entry: HistoryEntry

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text(entry.timestamp, format: .dateTime.month(.twoDigits).day(.twoDigits))
                    if let appName = entry.targetAppName {
                        Text("·")
                        Text(appName)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                textStageRow(text: entry.rawText)
                if let llm = entry.llmText {
                    textStageRow(text: llm, isRefined: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        private func textStageRow(text: String, isRefined: Bool = false) -> some View {
            let label: LocalizedStringKey = isRefined ? "LLM Refined" : "Transcription"
            return Text(text)
                .font(.system(size: 13))
                .foregroundStyle(isRefined ? Color.primary : Color.secondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .accessibilityLabel(Text("\(Text(label)): \(text)"))
                .padding(.leading, 10)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(isRefined ? Color.accentColor : Color.secondary.opacity(0.35))
                        .frame(width: 2)
                        .accessibilityHidden(true)
                }
        }
    }
#endif
