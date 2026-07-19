#if os(macOS)
    import MetalKit
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
                let elapsed = max(0, timeline.date.timeIntervalSince(startDate))
                let colors = MacDictationShaderStyling.orbColors(
                    for: state,
                    theme: shaderTheme,
                    elapsed: elapsed
                )

                MacDictationMetalEffectView(
                    size: CGSize(width: mainWidth, height: controlHeight),
                    startDate: startDate,
                    frameInterval: shaderFrameInterval,
                    signals: signals,
                    colors: colors,
                    isPaused: isPaused,
                    motionGain: 1.55
                )
                .frame(width: mainWidth, height: controlHeight)
                .clipShape(Capsule())
                .allowsHitTesting(false)
            }
        }
    }
#endif
