#if os(macOS)
    import HeatmapKit
    import SwiftUI

    struct MacDictationActivityHeatmapView: View {
        let contributions: [Date: Double]
        var now: Date = Date()
        var calendar: Calendar = .current

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                Text("Last 12 months")
                    .font(.headline)

                heatmap
                    .frame(maxWidth: .infinity, alignment: .leading)

                legend
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(MacUI.Surfaces.selection)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }

        private var heatmap: some View {
            let today = calendar.startOfDay(for: now)
            let start = calendar.date(byAdding: .day, value: -364, to: today) ?? today
            return CalendarHeatmap(
                contributions: contributions,
                dateRange: start...today
            )
            .levels(.orange)
            .cellSize(14)
            .cellSpacing(3)
            .cellCornerRadius(2)
            .firstWeekday(Weekday(rawValue: calendar.firstWeekday) ?? .sunday)
            .showMonthLabels(true)
            .showWeekdayLabels(true)
            .fitToWidth(minCellSize: 10)
            .tooltipOnTap(tooltip)
            .accessibilityCellLabel(tooltip)
        }

        private var legend: some View {
            HStack(spacing: 4) {
                Spacer(minLength: 0)
                Text("Less")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                ForEach(0..<5, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(legendFill(for: level))
                        .frame(width: 11, height: 11)
                }
                Text("More")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }

        private func legendFill(for level: Int) -> Color {
            switch level {
            case 1:
                return MacUI.Brand.orange.opacity(0.28)
            case 2:
                return MacUI.Brand.orange.opacity(0.48)
            case 3:
                return MacUI.Brand.orange.opacity(0.72)
            case 4:
                return MacUI.Brand.orange
            default:
                return MacUI.Surfaces.ink.opacity(0.08)
            }
        }

        private func tooltip(date: Date, value: Double) -> String {
            let day = date.formatted(date: .abbreviated, time: .omitted)
            let words = Int(value.rounded())
            if words <= 0 {
                return "No dictation on \(day)"
            }
            let label = words == 1 ? "1 word" : "\(words) words"
            return "\(day): \(label)"
        }
    }
#endif
