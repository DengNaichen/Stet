#if os(macOS)
    import SwiftUI

    struct MacDictationUsageStatsView: View {
        let summary: DictationUsageSummary

        var body: some View {
            LinearSectionGroup {
                HStack(spacing: 0) {
                    statCell(
                        value: summary.formattedDuration,
                        unit: "",
                        caption: "Total dictation time"
                    )

                    statCell(
                        value: summary.formattedWordCount,
                        unit: "words",
                        caption: "Words dictated"
                    )

                    statCell(
                        value: summary.formattedTimeSaved,
                        unit: "",
                        caption: "Time saved"
                    )

                    statCell(
                        value: summary.formattedWordsPerMinute,
                        unit: "WPM",
                        caption: "Average speed"
                    )
                }
            }
        }

        private func statCell(
            value: String,
            unit: String,
            caption: LocalizedStringKey
        ) -> some View {
            VStack(alignment: .leading, spacing: 4) {
                Text(caption)
                    .font(MacUI.LinearTypography.statLabel)
                    .foregroundStyle(MacUI.Foreground.secondary)
                    .lineLimit(1)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .font(MacUI.LinearTypography.statValue)
                        .monospacedDigit()
                        .foregroundStyle(MacUI.Foreground.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    if !unit.isEmpty {
                        Text(LocalizedStringKey(unit))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(MacUI.Foreground.secondary)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
#endif
