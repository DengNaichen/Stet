#if os(macOS)
    import SwiftUI

    struct MacDictationUsageStatsView: View {
        let summary: DictationUsageSummary

        var body: some View {
            LinearSectionGroup {
                HStack(spacing: 0) {
                    statCell(
                        value: Self.localizedDuration(summary.totalDuration),
                        unit: nil,
                        caption: "Total dictation time"
                    )

                    statCell(
                        value: summary.formattedWordCount,
                        unit: "words",
                        caption: "Words dictated"
                    )

                    statCell(
                        value: Self.localizedDuration(summary.timeSaved),
                        unit: nil,
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

        static func localizedDuration(_ duration: TimeInterval) -> String {
            let totalSeconds = max(0, Int(duration.rounded()))
            let hours = totalSeconds / 3_600
            let minutes = (totalSeconds % 3_600) / 60
            let seconds = totalSeconds % 60

            if hours > 0, minutes > 0 {
                return String(localized: "\(hours) hr \(minutes) min")
            }
            if hours > 0 {
                return String(localized: "\(hours) hr")
            }
            if minutes > 0 {
                return String(localized: "\(minutes) min")
            }
            return String(localized: "\(seconds) sec")
        }

        private func statCell(
            value: String,
            unit: LocalizedStringKey?,
            caption: LocalizedStringKey
        ) -> some View {
            VStack(alignment: .leading, spacing: 4) {
                Text(caption)
                    .font(MacUI.LinearTypography.statLabel)
                    .foregroundStyle(MacUI.Foreground.secondary)
                    .lineLimit(1)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(verbatim: value)
                        .font(MacUI.LinearTypography.statValue)
                        .monospacedDigit()
                        .foregroundStyle(MacUI.Foreground.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    if let unit {
                        Text(unit)
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
