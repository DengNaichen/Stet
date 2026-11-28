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

    var body: some View {
        NavigationStack {
            List {
                activityOverviewSection
                historyEntriesSection
            }
            .listStyle(.insetGrouped)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $viewModel.searchText, prompt: "Search transcripts or apps")
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
                        Image(systemName: "ellipsis.circle")
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

    private var activityOverviewSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    HistoryStatTile(
                        title: "Words",
                        value: viewModel.usageSummary.formattedWordCount,
                        systemImage: "text.word.spacing",
                        tint: .orange
                    )
                    HistoryStatTile(
                        title: "Sessions",
                        value: DictationUsageSummary.formatCompactCount(viewModel.usageSummary.sessionCount),
                        systemImage: "waveform",
                        tint: .indigo
                    )
                    HistoryStatTile(
                        title: "Time Saved",
                        value: viewModel.usageSummary.formattedTimeSaved,
                        systemImage: "clock.badge.checkmark",
                        tint: .green
                    )
                }

                HistoryActivityHeatmapView(details: viewModel.activityDetails)
            }
            .padding(.vertical, 4)
        } header: {
            Text("Activity")
        } footer: {
            Text("Synced automatically via iCloud across Mac and iPhone.")
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
                    Label("No Dictation History Yet", systemImage: "clock.arrow.circlepath")
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
                        }
                    )
                }
            } header: {
                Text(isSearching ? "Results" : "Recent Dictations")
            } footer: {
                Text("Tap any entry to copy. Touch and hold for more copy options.")
            }
        }
    }

    private var isSearching: Bool {
        !viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func copyText(_ text: String, itemID: UUID) {
        UIPasteboard.general.string = text
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.spring(response: 0.25, dampingFraction: 1.0)) {
            copiedItemID = itemID
        }
        copyResetTask?.cancel()
        copyResetTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.25, dampingFraction: 1.0)) {
                if copiedItemID == itemID {
                    copiedItemID = nil
                }
            }
        }
    }
}

private struct HistoryStatTile: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(.tertiarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }
}

private struct HistoryActivityHeatmapView: View {
    let details: [Date: DictationDailySummary]
    var now: Date = Date()
    var calendar: Calendar = .current
    var weeksCount: Int = 14

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let today = calendar.startOfDay(for: now)
        let gridStart = computeGridStart(today: today)
        let peakWords = maxWordCount(from: gridStart, through: today)

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Last \(weeksCount) Weeks")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                legend
            }

            HStack(spacing: 3) {
                ForEach(0..<weeksCount, id: \.self) { week in
                    VStack(spacing: 3) {
                        ForEach(0..<7, id: \.self) { dayOffset in
                            cell(
                                date: calendar.date(byAdding: .day, value: week * 7 + dayOffset, to: gridStart),
                                today: today,
                                peakWords: peakWords
                            )
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Dictation activity heatmap for the last \(weeksCount) weeks")
        }
    }

    @ViewBuilder
    private func cell(date: Date?, today: Date, peakWords: Int) -> some View {
        if let date, date <= today {
            let day = calendar.startOfDay(for: date)
            let words = details[day]?.wordCount ?? 0
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(cellColor(for: intensityLevel(words: words, peakWords: peakWords)))
                .aspectRatio(1, contentMode: .fit)
        } else {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
        }
    }

    private var legend: some View {
        HStack(spacing: 3) {
            Text("Less")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            ForEach(0..<5, id: \.self) { level in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(cellColor(for: level))
                    .frame(width: 9, height: 9)
            }
            Text("More")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func computeGridStart(today: Date) -> Date {
        let currentWeekStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        return calendar.date(byAdding: .day, value: -(weeksCount - 1) * 7, to: currentWeekStart) ?? today
    }

    private func maxWordCount(from start: Date, through today: Date) -> Int {
        details.reduce(0) { partialResult, pair in
            guard pair.key >= start, pair.key <= today else { return partialResult }
            return max(partialResult, pair.value.wordCount)
        }
    }

    private func intensityLevel(words: Int, peakWords: Int) -> Int {
        guard words > 0 else { return 0 }
        let denominator = Double(max(peakWords, 40))
        let ratio = Double(words) / denominator
        if ratio >= 0.75 {
            return 4
        }
        if ratio >= 0.45 {
            return 3
        }
        if ratio >= 0.2 {
            return 2
        }
        return 1
    }

    private func cellColor(for level: Int) -> Color {
        switch level {
        case 1:
            return Color.orange.opacity(colorScheme == .dark ? 0.34 : 0.28)
        case 2:
            return Color.orange.opacity(colorScheme == .dark ? 0.56 : 0.50)
        case 3:
            return Color.orange.opacity(colorScheme == .dark ? 0.78 : 0.72)
        case 4:
            return Color.orange
        default:
            return Color.primary.opacity(colorScheme == .dark ? 0.11 : 0.07)
        }
    }
}

private struct HistoryEntryRowView: View {
    let item: HistoryItem
    let isCopied: Bool
    let onCopyFinal: () -> Void
    let onCopyRaw: () -> Void

    var body: some View {
        Button {
            onCopyFinal()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(item.timestamp, format: .dateTime.month(.abbreviated).day().hour().minute())
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)

                    if let appName = item.appDisplayName {
                        Text(appName)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color(.tertiarySystemFill), in: Capsule())
                            .lineLimit(1)
                    }

                    if item.isRewritten {
                        Label("Rewritten", systemImage: "sparkles")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.purple)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.14), in: Capsule())
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    if isCopied {
                        Label("Copied", systemImage: "checkmark")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.green)
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }
                }

                Text(item.displayText)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                onCopyFinal()
            } label: {
                Label("Copy Final", systemImage: "doc.on.doc")
            }

            if item.hasDistinctRawText {
                Button {
                    onCopyRaw()
                } label: {
                    Label("Copy Raw", systemImage: "doc.plaintext")
                }
            }
        }
        .accessibilityHint("Tap to copy text")
    }
}

#if DEBUG
    #Preview {
        HistoryView()
    }
#endif
