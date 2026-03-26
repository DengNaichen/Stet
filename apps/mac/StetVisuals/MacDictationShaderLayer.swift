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
                            a: colors.a,
                            b: colors.b,
                            c: colors.c
                        )
                    )
                    .frame(width: mainWidth, height: controlHeight)
                    .allowsHitTesting(false)
            }
        }

        private func currentSignals(elapsed: Double) -> MacDictationCapsuleVisualSignals {
            if case .processing = state {
                // 指数曲线进度：快速启动，然后减速，永远不到 100%
                // Clamp elapsed to prevent negative or huge values
                let clampedElapsed = max(0, elapsed)
                let progress = min(0.95, 1.0 - exp(-clampedElapsed * 1.2))
                
                // body 表示进度，presence 保持高位表示活跃，其他信号静默
                return MacDictationCapsuleVisualSignals(
                    body: progress,
                    presence: 0.70,
                    pulse: 0.0,
                    articulation: 0.0
                )
            }

            return signals
        }


    }
#endif
