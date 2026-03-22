#if os(macOS)
import SwiftUI

struct MacDictationShaderLayer: View {
    let state: MacDictationCapsuleVisualState
    let mainWidth: CGFloat
    let controlHeight: CGFloat
    let startDate: Date
    let shaderFrameInterval: Double
    let signals: MacDictationCapsuleVisualSignals
    let shaderTheme: MacDictationShaderTheme
    let isPaused: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: shaderFrameInterval, paused: isPaused)) { timeline in
            let elapsed = timeline.date.timeIntervalSince(startDate)
            let effectiveSignals = currentSignals(elapsed: elapsed)
            let isProcessing = isProcessingState

            let shaderDetail = MacDictationShaderStyling.detail(
                for: state,
                signals: effectiveSignals
            )
            let colors = MacDictationShaderStyling.colors(
                for: state,
                theme: shaderTheme,
                elapsed: elapsed,
                signals: effectiveSignals
            )

            Capsule().fill(.white)
                .colorEffect(
                    StetVisualsShaderLibrary.cloudOrbGlassWide(
                        size: CGSize(width: mainWidth, height: controlHeight),
                        time: elapsed,
                        body: effectiveSignals.body,
                        presence: effectiveSignals.presence,
                        pulse: effectiveSignals.pulse,
                        articulation: effectiveSignals.articulation,
                        detail: shaderDetail,
                        top: colors.top,
                        mid: colors.mid,
                        low: colors.low
                    )
                )
                .overlay {
                    if isProcessing {
                        processingOverlay(elapsed: elapsed)
                    }
                }
                .frame(width: mainWidth, height: controlHeight)
                .allowsHitTesting(false)
        }
    }

    private func currentSignals(elapsed: Double) -> MacDictationCapsuleVisualSignals {
        if case .processing = state {
            return MacDictationCapsuleVisualSignals(
                body: 0.32 + 0.06 * sin(elapsed * 1.4),
                presence: 0.42 + 0.08 * sin(elapsed * 0.9 + 0.8),
                pulse: 0.20 + 0.12 * max(0, sin(elapsed * 2.2)),
                articulation: 0.34 + 0.10 * sin(elapsed * 2.8 + 1.1)
            )
        }

        return signals
    }

    private var isProcessingState: Bool {
        if case .processing = state {
            return true
        }

        return false
    }

    @ViewBuilder
    private func processingOverlay(elapsed: Double) -> some View {
        let primaryOffset = sweepOffset(
            elapsed: elapsed,
            speed: 0.34,
            phase: 0.0,
            spanMultiplier: 1.34
        )
        let secondaryOffset = sweepOffset(
            elapsed: elapsed,
            speed: 0.46,
            phase: 0.58,
            spanMultiplier: 1.22
        )
        let edgePulse = 0.52 + 0.22 * sin(elapsed * 2.1)

        ZStack {
            Capsule()
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.05),
                            Color.orange.opacity(0.20),
                            Color.white.opacity(0.05)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    lineWidth: 1
                )
                .opacity(edgePulse)

            Capsule()
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.0),
                            .init(color: Color.white.opacity(0.00), location: 0.24),
                            .init(color: Color.white.opacity(0.14), location: 0.42),
                            .init(color: Color.orange.opacity(0.34), location: 0.58),
                            .init(color: Color.orange.opacity(0.08), location: 0.72),
                            .init(color: .clear, location: 1.0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: mainWidth * 0.46, height: controlHeight * 0.96)
                .blur(radius: 9)
                .offset(x: primaryOffset)

            Capsule()
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.0),
                            .init(color: Color.white.opacity(0.00), location: 0.18),
                            .init(color: Color.orange.opacity(0.12), location: 0.45),
                            .init(color: Color.yellow.opacity(0.20), location: 0.56),
                            .init(color: Color.orange.opacity(0.10), location: 0.70),
                            .init(color: .clear, location: 1.0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: mainWidth * 0.30, height: controlHeight * 0.84)
                .blur(radius: 7)
                .offset(x: secondaryOffset)
        }
        .blendMode(.screen)
        .compositingGroup()
        .allowsHitTesting(false)
    }

    private func sweepOffset(
        elapsed: Double,
        speed: Double,
        phase: Double,
        spanMultiplier: Double
    ) -> CGFloat {
        let progress = (elapsed * speed + phase).truncatingRemainder(dividingBy: 1.0)
        let normalized = progress * 2.0 - 1.0
        return CGFloat(normalized * spanMultiplier) * mainWidth * 0.5
    }
}
#endif
