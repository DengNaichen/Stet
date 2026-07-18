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
                let isProcessing = isProcessingState
                let colors = MacDictationShaderStyling.orbColors(
                    for: state,
                    theme: shaderTheme,
                    elapsed: elapsed
                )

                MacDictationMetalEffectView(
                    size: CGSize(width: mainWidth, height: controlHeight),
                    startDate: startDate,
                    frameInterval: shaderFrameInterval,
                    signals: currentSignals(),
                    colors: colors,
                    isPaused: isPaused,
                    motionGain: 1,
                    processingMix: isProcessing ? 1 : 0
                )
                .frame(width: mainWidth, height: controlHeight)
                .clipShape(Capsule())
                .allowsHitTesting(false)
            }
        }

        private var isProcessingState: Bool {
            if case .processing = state {
                return true
            }

            return false
        }

        private func currentSignals() -> MacDictationCapsuleVisualSignals {
            switch state {
            case .starting, .listening:
                return signals
            case .processing:
                return signals.scaled(by: 0.35)
            case .hidden, .result, .error:
                return .zero
            }
        }
    }
#endif
