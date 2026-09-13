#if os(macOS)
    import SwiftUI

    struct MacDictationUsageStatsView: View {
        let summary: DictationUsageSummary

        private let columns = [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10),
        ]

        var body: some View {
            LazyVGrid(columns: columns, spacing: 10) {
                card(
                    value: summary.formattedDuration,
                    unit: "",
                    caption: "Total dictation time"
                )
                card(
                    value: summary.formattedWordCount,
                    unit: "words",
                    caption: "Words dictated"
                )
                card(
                    value: summary.formattedTimeSaved,
                    unit: "",
                    caption: "Time saved"
                )
                card(
                    value: summary.formattedWordsPerMinute,
                    unit: "WPM",
                    caption: "Average dictation speed"
                )
            }
        }

        private func card(
            value: String,
            unit: String,
            caption: String
        ) -> some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(value)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(MacUI.Surfaces.ink)
                    if !unit.isEmpty {
                        Text(LocalizedStringKey(unit))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }

                Text(LocalizedStringKey(caption))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(MacUI.Surfaces.selection)
            )
        }
    }
#endif
