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
                    systemImage: "clock",
                    value: summary.formattedDuration,
                    unit: "",
                    caption: "Total dictation time"
                )
                card(
                    systemImage: "mic",
                    value: summary.formattedWordCount,
                    unit: "words",
                    caption: "Words dictated"
                )
                card(
                    systemImage: "hourglass",
                    value: summary.formattedTimeSaved,
                    unit: "",
                    caption: "Time saved"
                )
                card(
                    systemImage: "bolt.fill",
                    value: summary.formattedWordsPerMinute,
                    unit: "WPM",
                    caption: "Average dictation speed"
                )
            }
        }

        private func card(
            systemImage: String,
            value: String,
            unit: String,
            caption: String
        ) -> some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 16)

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
                }

                Text(LocalizedStringKey(caption))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 24)
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
