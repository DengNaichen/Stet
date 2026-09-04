#if os(macOS)
    import AppKit
    import StetCore
    import SwiftUI
    import UniformTypeIdentifiers

    struct MacHistorySettingsView: View {
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
                    || ($0.finalText?.lowercased().contains(q) == true)
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
                        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                }
                .listStyle(.plain)
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

        @State private var isExpanded = false

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                // Header row
                HStack(spacing: 6) {
                    statusBadge
                    if let appName = entry.targetAppName {
                        Text(appName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .imageScale(.small)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                // Primary text — always visible
                Text(displayText)
                    .font(.system(size: 13))
                    .lineLimit(isExpanded ? nil : 2)
                    .fixedSize(horizontal: false, vertical: isExpanded)

                // Expanded detail
                if isExpanded {
                    expandedDetail
                }
            }
        }

        private var displayText: String {
            entry.llmText ?? entry.rawText
        }

        @ViewBuilder
        private var statusBadge: some View {
            let (label, color): (LocalizedStringKey, Color) = {
                switch entry.status {
                case .completed:
                    return (LocalizedStringKey("Sent"), .green)
                case .clipboardPending:
                    return (LocalizedStringKey("Clipboard"), .orange)
                case .processing:
                    return (LocalizedStringKey("Transcribed"), .secondary)
                case .notDelivered:
                    return (LocalizedStringKey("Transcribed"), .secondary)
                }
            }()
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(color.opacity(0.15))
                .foregroundStyle(color)
                .clipShape(Capsule())
        }

        @ViewBuilder
        private var expandedDetail: some View {
            VStack(alignment: .leading, spacing: 8) {
                Divider()
                textStageRow(label: LocalizedStringKey("Transcript"), text: entry.rawText)
                if let llm = entry.llmText, llm != entry.rawText {
                    textStageRow(label: LocalizedStringKey("LLM Refined"), text: llm)
                }
                if let final = entry.finalText {
                    textStageRow(label: LocalizedStringKey("Delivered"), text: final)
                }
                if let bundleID = entry.targetBundleID {
                    labeledRow(label: LocalizedStringKey("Target App"), value: bundleID)
                }
            }
            .padding(.top, 2)
        }

        private func textStageRow(label: LocalizedStringKey, text: String) -> some View {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(text)
                    .font(.system(size: 12))
                    .textSelection(.enabled)
            }
        }

        private func labeledRow(label: LocalizedStringKey, value: String) -> some View {
            HStack(alignment: .top, spacing: 4) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption)
                    .textSelection(.enabled)
            }
        }
    }
#endif
