import SwiftUI

/// Visual meter for microphone input level.
struct MicrophoneAudioLevelMeter: View {
    let level: Double

    private let barCount = 20
    private let spacing: CGFloat = 2

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: spacing) {
                ForEach(0..<barCount, id: \.self) { index in
                    MicrophoneAudioLevelBar(
                        isActive: isBarActive(index: index),
                        height: barHeight(for: index, in: geometry.size.height)
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 40)
        .accessibilityLabel("Microphone input level")
    }

    private func isBarActive(index: Int) -> Bool {
        let threshold = Double(index) / Double(barCount)
        return level >= threshold
    }

    private func barHeight(for index: Int, in totalHeight: CGFloat) -> CGFloat {
        let centerIndex = barCount / 2
        let distanceFromCenter = abs(index - centerIndex)
        let maxHeight = totalHeight * 0.3
        let minHeight: CGFloat = 4

        let heightFactor = 1.0 - (Double(distanceFromCenter) / Double(centerIndex)) * 0.5
        return minHeight + (maxHeight - minHeight) * CGFloat(heightFactor)
    }
}

private struct MicrophoneAudioLevelBar: View {
    let isActive: Bool
    let height: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(isActive ? .green : Color.gray.opacity(0.3))
            .frame(height: height)
            .animation(.easeInOut(duration: 0.1), value: isActive)
    }
}
