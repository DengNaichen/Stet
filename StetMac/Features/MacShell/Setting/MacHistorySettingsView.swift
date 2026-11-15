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
            let query = searchText.lowercased()
            return entries.filter {
                $0.rawText.lowercased().contains(query)
                    || ($0.llmText?.lowercased().contains(query) == true)
                    || ($0.targetAppName?.lowercased().contains(query) == true)
                    || ($0.targetBundleID?.lowercased().contains(query) == true)
            }
        }

        var body: some View {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    LinearSearchField(
                        placeholder: "Search History",
                        text: $searchText,
                        height: 29,
                        fillColor: MacUI.LinearSurfaces.glassInset,
                        isBorderless: true
                    )
                    if !entries.isEmpty {
                        LinearBadge(text: "\(filtered.count)")
                    }
                }
                .frame(maxWidth: MacUI.LinearMetrics.contentMaxWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, MacUI.LinearMetrics.contentHorizontalPadding)
                .padding(.top, MacUI.LinearMetrics.contentTopPadding)
                .padding(.bottom, 8)

                content
            }
            .macNativeNavigationChrome(
                title: "History",
                preservesExpandedToolbar: false
            )
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        reload()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .help("Refresh history")

                    Button {
                        exportJSON()
                    } label: {
                        Label("Export JSON", systemImage: "square.and.arrow.up")
                    }
                    .disabled(entries.isEmpty)
                    .help("Export history as JSON")

                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Clear All", systemImage: "trash")
                    }
                    .disabled(entries.isEmpty)
                    .help("Clear all history")
                }
            }
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
            .task { reload() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { reload() } }
        }

        @ViewBuilder
        private var content: some View {
            if let loadError {
                ContentUnavailableView(
                    LocalizedStringKey("Could not load history"),
                    systemImage: "exclamationmark.triangle",
                    description: Text(loadError)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(filtered, id: \.id) { entry in
                            HistoryEntryRow(entry: entry)
                        }
                    }
                    .frame(maxWidth: MacUI.LinearMetrics.contentMaxWidth, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, MacUI.LinearMetrics.contentHorizontalPadding)
                    .padding(.vertical, 16)
                }
                .macSettingsScrollIndicator()
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
        @State private var didCopy = false

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Text(entry.timestamp, format: .dateTime.month(.twoDigits).day(.twoDigits).hour().minute())
                        .font(MacUI.LinearTypography.rowSubtitle)
                        .foregroundStyle(MacUI.LinearSurfaces.mutedInk)

                    if let appName = entry.targetAppName {
                        Text("·")
                            .foregroundStyle(MacUI.LinearSurfaces.mutedInk)
                        LinearBadge(text: appName)
                    }

                    Spacer(minLength: 8)

                    Button {
                        copyPrimaryText()
                    } label: {
                        Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(didCopy ? MacUI.Foreground.success : MacUI.Foreground.secondaryColor)
                    }
                    .buttonStyle(.plain)
                    .help("Copy text")
                    .accessibilityLabel("Copy transcript")
                }

                textStageRow(text: entry.rawText)
                if let llm = entry.llmText {
                    textStageRow(text: llm, isRefined: true)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: MacUI.LinearMetrics.cardCornerRadius, style: .continuous)
                    .fill(MacUI.LinearSurfaces.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: MacUI.LinearMetrics.cardCornerRadius, style: .continuous)
                    .strokeBorder(MacUI.LinearSurfaces.hairline, lineWidth: 1)
            )
        }

        private func textStageRow(text: String, isRefined: Bool = false) -> some View {
            let label: LocalizedStringKey = isRefined ? "LLM Refined" : "Transcription"
            return Text(text)
                .font(.system(size: 12.5))
                .foregroundStyle(isRefined ? MacUI.Foreground.primary : MacUI.Foreground.secondaryColor)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .accessibilityLabel(Text("\(Text(label)): \(text)"))
                .padding(.leading, 10)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(isRefined ? MacUI.LinearBrand.accent : MacUI.LinearSurfaces.hairlineStrong)
                        .frame(width: 2)
                        .accessibilityHidden(true)
                }
        }

        private func copyPrimaryText() {
            let value = entry.llmText ?? entry.rawText
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
            didCopy = true
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.2))
                didCopy = false
            }
        }
    }
#endif
