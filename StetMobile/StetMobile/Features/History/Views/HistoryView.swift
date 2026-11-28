import Foundation
import StetCore
import SwiftUI
import UIKit

struct HistoryView: View {
    @StateObject private var viewModel = HistoryViewModel()
    @Environment(\.scenePhase) private var scenePhase

    @State private var showClearConfirmation = false
    @State private var copiedItemID: UUID?
    @State private var copyResetTask: Task<Void, Never>?
    @State private var inspectedItem: HistoryItem?

    var body: some View {
        NavigationStack {
            List {
                historyEntriesSection
            }
            .listStyle(.insetGrouped)
            .scrollDismissesKeyboard(.interactively)
            .linearInlineHeader("History")
            .searchable(
                text: $viewModel.searchText,
                placement: .navigationBarDrawer(displayMode: .automatic),
                prompt: "Search transcripts or apps"
            )
            .refreshable {
                viewModel.reload()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            viewModel.reload()
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }

                        Button(role: .destructive) {
                            showClearConfirmation = true
                        } label: {
                            Label("Clear All", systemImage: "trash")
                        }
                        .disabled(viewModel.entries.isEmpty)
                    } label: {
                        Image(systemName: "ellipsis")
                            .accessibilityLabel("History actions")
                    }
                }
            }
            .confirmationDialog(
                "Clear all history?",
                isPresented: $showClearConfirmation,
                titleVisibility: .visible
            ) {
                Button("Clear All", role: .destructive) {
                    withAnimation {
                        viewModel.deleteAll()
                    }
                }
            } message: {
                Text("This removes synced dictation history across your devices and cannot be undone.")
            }
            .sheet(item: $inspectedItem) { item in
                HistoryEntryDetailSheet(
                    item: item,
                    onCopyFinal: {
                        copyText(item.displayText, itemID: item.id)
                    },
                    onCopyRaw: {
                        copyText(item.trimmedRawText, itemID: item.id)
                    }
                )
            }
            .task {
                viewModel.reload()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    viewModel.reload()
                }
            }
            .onDisappear {
                copyResetTask?.cancel()
            }
        }
    }

    @ViewBuilder
    private var historyEntriesSection: some View {
        if let loadError = viewModel.loadError {
            ContentUnavailableView(
                "Could Not Load History",
                systemImage: "exclamationmark.triangle",
                description: Text(loadError)
            )
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .padding(.vertical, 24)
        } else if viewModel.filteredEntries.isEmpty {
            if isSearching {
                ContentUnavailableView.search(text: viewModel.searchText)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .padding(.vertical, 24)
            } else {
                ContentUnavailableView {
                    Label("No Dictation History Yet", systemImage: "clock")
                } description: {
                    Text(
                        "Dictations from your Mac and iPhone sync automatically via iCloud and appear here."
                    )
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .padding(.vertical, 24)
            }
        } else {
            Section {
                ForEach(viewModel.filteredEntries) { item in
                    HistoryEntryRowView(
                        item: item,
                        isCopied: copiedItemID == item.id,
                        onCopyFinal: {
                            copyText(item.displayText, itemID: item.id)
                        },
                        onCopyRaw: {
                            copyText(item.trimmedRawText, itemID: item.id)
                        },
                        onInspect: {
                            inspectedItem = item
                        }
                    )
                }
            } header: {
                Text(isSearching ? "Results" : "Recent Dictations")
            } footer: {
                Text("Tap to copy. Touch and hold to inspect raw transcript.")
            }
        }
    }

    private var isSearching: Bool {
        !viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func copyText(_ text: String, itemID: UUID) {
        UIPasteboard.general.string = text
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.easeOut(duration: 0.18)) {
            copiedItemID = itemID
        }
        copyResetTask?.cancel()
        copyResetTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                if copiedItemID == itemID {
                    copiedItemID = nil
                }
            }
        }
    }
}

private struct HistoryEntryRowView: View {
    let item: HistoryItem
    let isCopied: Bool
    let onCopyFinal: () -> Void
    let onCopyRaw: () -> Void
    let onInspect: () -> Void

    var body: some View {
        Button {
            onCopyFinal()
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Text(metadataLine)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 8)
                }
                .overlay(alignment: .trailing) {
                    Text("Copied")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(MobileLinearPalette.accentAmber)
                        .opacity(isCopied ? 1 : 0)
                        .allowsHitTesting(false)
                }

                Text(normalizedDisplayText)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineSpacing(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                onCopyFinal()
            } label: {
                Label("Copy Text", systemImage: "doc.on.doc")
            }

            if item.hasDistinctRawText {
                Button {
                    onCopyRaw()
                } label: {
                    Label("Copy Raw", systemImage: "doc.plaintext")
                }

                Button {
                    onInspect()
                } label: {
                    Label("Compare Raw & Refined", systemImage: "text.alignleft")
                }
            }
        }
        .accessibilityHint("Tap to copy text")
    }

    private var metadataLine: String {
        var parts: [String] = [
            item.timestamp.formatted(.dateTime.month(.abbreviated).day().hour().minute())
        ]
        if let appName = item.appDisplayName {
            parts.append(appName)
        }
        if item.isRewritten {
            parts.append("Refined")
        }
        return parts.joined(separator: " · ")
    }

    private var normalizedDisplayText: String {
        item.displayText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }
}

private struct HistoryEntryDetailSheet: View {
    let item: HistoryItem
    let onCopyFinal: () -> Void
    let onCopyRaw: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    stageBlock(
                        title: "Transcription",
                        text: item.trimmedRawText,
                        barColor: Color.primary.opacity(0.22),
                        textColor: .secondary
                    )

                    if item.hasDistinctRawText {
                        stageBlock(
                            title: "Refined",
                            text: item.displayText,
                            barColor: MobileLinearPalette.accentAmber,
                            textColor: .primary
                        )
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(item.appDisplayName ?? "Transcript")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Copy Raw") {
                        onCopyRaw()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Copy Refined") {
                        onCopyFinal()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func stageBlock(
        title: String,
        text: String,
        barColor: Color,
        textColor: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(text)
                .font(.body)
                .foregroundStyle(textColor)
                .lineSpacing(4)
                .textSelection(.enabled)
                .padding(.leading, 12)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(barColor)
                        .frame(width: 2)
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#if DEBUG
    #Preview {
        HistoryView()
    }
#endif
