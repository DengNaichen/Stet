import Foundation
import StetCore
import SwiftUI

struct OverviewView: View {
    @StateObject private var viewModel = OverviewViewModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedDay: Date?

    var body: some View {
        NavigationStack {
            List {
                rangeAndStatsSection
                heatmapSection
                if !viewModel.appUsage.isEmpty {
                    appUsageSection
                }
            }
            .listStyle(.insetGrouped)
            .linearInlineHeader("Overview")
            .refreshable {
                viewModel.reload()
            }
            .task {
                viewModel.reload()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    viewModel.reload()
                }
            }
        }
    }

    private var rangeAndStatsSection: some View {
        Section {
            VStack(spacing: 14) {
                Picker("Range", selection: $viewModel.selectedRange) {
                    ForEach(OverviewTimeRange.allCases) { range in
                        Text(range.shortTitle).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: viewModel.selectedRange) { _, _ in
                    selectedDay = nil
                }

                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        statCell(
                            label: "Words",
                            value: viewModel.usageSummary.formattedWordCount
                        )
                        Divider()
                            .frame(height: 36)
                        statCell(
                            label: "Sessions",
                            value: DictationUsageSummary.formatCompactCount(viewModel.usageSummary.sessionCount)
                        )
                    }
                    .padding(.bottom, 10)

                    Divider()

                    HStack(spacing: 0) {
                        statCell(
                            label: "Time Saved",
                            value: Self.compactDuration(viewModel.usageSummary.timeSaved)
                        )
                        Divider()
                            .frame(height: 36)
                        statCell(
                            label: "Avg Speed",
                            value: viewModel.usageSummary.averageWordsPerMinute == nil
                                ? "—"
                                : "\(viewModel.usageSummary.formattedWordsPerMinute) WPM"
                        )
                    }
                    .padding(.top, 10)
                }
            }
            .padding(.vertical, 4)
        } footer: {
            Text("Compared against typing at 40 WPM · Synced via iCloud.")
        }
    }

    private var heatmapSection: some View {
        Section {
            CompactActivityHeatmapView(
                details: viewModel.activityDetails,
                range: viewModel.selectedRange,
                selectedDay: $selectedDay
            )
            .padding(.vertical, 4)
        } header: {
            HStack {
                Text("Activity")
                Spacer()
                if let selectedDay {
                    let words = viewModel.activityDetails[selectedDay]?.formattedWordCount ?? "0"
                    Text("\(selectedDay.formatted(.dateTime.month(.abbreviated).day())) · \(words) words")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                }
            }
        }
    }

    private var appUsageSection: some View {
        Section("By App") {
            ForEach(viewModel.appUsage) { app in
                HStack(spacing: 12) {
                    Text(app.id == DictationAppUsage.otherID ? "Other" : app.name)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .frame(minWidth: 76, alignment: .leading)

                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.primary.opacity(0.08))
                            Capsule()
                                .fill(MobileLinearPalette.accentAmber)
                                .frame(width: max(4, proxy.size.width * CGFloat(min(max(app.share, 0), 1))))
                        }
                    }
                    .frame(height: 4)

                    Text(app.formattedWordCount)
                        .font(.caption.monospacedDigit().weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 42, alignment: .trailing)
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func statCell(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
    }

    private static func compactDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration.rounded()))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60

        if hours > 0, minutes > 0 {
            return "\(hours)h \(minutes)m"
        }
        if hours > 0 {
            return "\(hours)h"
        }
        if minutes > 0 {
            return "\(minutes)m"
        }
        return "\(seconds)s"
    }
}

private struct CompactActivityHeatmapView: View {
    let details: [Date: DictationDailySummary]
    let range: OverviewTimeRange
    @Binding var selectedDay: Date?

    var now: Date = Date()
    var calendar: Calendar = .current

    @Environment(\.colorScheme) private var colorScheme

    private let cellSize: CGFloat = 10
    private let cellSpacing: CGFloat = 3

    var body: some View {
        let today = calendar.startOfDay(for: now)
        let weeks = range.weeksCount
        let gridStart = computeGridStart(today: today, weeks: weeks)
        let peakWords = maxWordCount(from: gridStart, through: today)

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 6) {
                weekdayColumn
                    .padding(.top, 16)

                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 4) {
                        monthHeaderRow(gridStart: gridStart, weeks: weeks)

                        HStack(spacing: cellSpacing) {
                            ForEach(0..<weeks, id: \.self) { week in
                                VStack(spacing: cellSpacing) {
                                    ForEach(0..<7, id: \.self) { dayOffset in
                                        cell(
                                            date: calendar.date(
                                                byAdding: .day,
                                                value: week * 7 + dayOffset,
                                                to: gridStart
                                            ),
                                            today: today,
                                            peakWords: peakWords
                                        )
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 1)
                }
                .defaultScrollAnchor(.trailing)
            }

            HStack {
                Text("Last \(range.daySpan) days")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                legend
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Dictation activity heatmap for the last \(range.daySpan) days")
    }

    private var weekdayColumn: some View {
        VStack(spacing: cellSpacing) {
            ForEach(0..<7, id: \.self) { index in
                Text(weekdayLabel(for: index))
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .frame(width: 12, height: cellSize, alignment: .leading)
            }
        }
    }

    private func weekdayLabel(for row: Int) -> String {
        switch row {
        case 1: "M"
        case 3: "W"
        case 5: "F"
        default: ""
        }
    }

    private func monthHeaderRow(gridStart: Date, weeks: Int) -> some View {
        HStack(spacing: cellSpacing) {
            ForEach(0..<weeks, id: \.self) { week in
                let label = monthLabel(for: week, gridStart: gridStart)
                Text(label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
                    .frame(width: cellSize, height: 12, alignment: .leading)
            }
        }
    }

    private func monthLabel(for week: Int, gridStart: Date) -> String {
        guard let weekDate = calendar.date(byAdding: .day, value: week * 7, to: gridStart) else {
            return ""
        }
        let month = calendar.component(.month, from: weekDate)
        if week == 0 {
            return weekDate.formatted(.dateTime.month(.abbreviated))
        }
        guard let prevDate = calendar.date(byAdding: .day, value: (week - 1) * 7, to: gridStart) else {
            return ""
        }
        let prevMonth = calendar.component(.month, from: prevDate)
        return month != prevMonth ? weekDate.formatted(.dateTime.month(.abbreviated)) : ""
    }

    @ViewBuilder
    private func cell(date: Date?, today: Date, peakWords: Int) -> some View {
        if let date, date <= today {
            let day = calendar.startOfDay(for: date)
            let words = details[day]?.wordCount ?? 0
            let isSelected = selectedDay == day
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .fill(cellColor(for: intensityLevel(words: words, peakWords: peakWords)))
                .frame(width: cellSize, height: cellSize)
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                            .strokeBorder(Color.primary, lineWidth: 1)
                    }
                }
                .onTapGesture {
                    selectedDay = isSelected ? nil : day
                }
        } else {
            Color.clear
                .frame(width: cellSize, height: cellSize)
        }
    }

    private var legend: some View {
        HStack(spacing: 3) {
            Text("Less")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            ForEach(0..<5, id: \.self) { level in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(cellColor(for: level))
                    .frame(width: 8, height: 8)
            }
            Text("More")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
    }

    private func computeGridStart(today: Date, weeks: Int) -> Date {
        let currentWeekStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        return calendar.date(byAdding: .day, value: -(weeks - 1) * 7, to: currentWeekStart) ?? today
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
        if ratio >= 0.75 { return 4 }
        if ratio >= 0.45 { return 3 }
        if ratio >= 0.20 { return 2 }
        return 1
    }

    private func cellColor(for level: Int) -> Color {
        switch level {
        case 1:
            return MobileLinearPalette.accentAmber.opacity(colorScheme == .dark ? 0.28 : 0.25)
        case 2:
            return MobileLinearPalette.accentAmber.opacity(colorScheme == .dark ? 0.50 : 0.48)
        case 3:
            return MobileLinearPalette.accentAmber.opacity(colorScheme == .dark ? 0.74 : 0.72)
        case 4:
            return MobileLinearPalette.accentAmber
        default:
            return Color.primary.opacity(colorScheme == .dark ? 0.09 : 0.06)
        }
    }
}
