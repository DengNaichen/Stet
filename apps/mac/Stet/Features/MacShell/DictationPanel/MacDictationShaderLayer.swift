#if os(macOS)
import SwiftUI

struct MacDictationShaderLayer: View {
    let state: DictationState
    let mainWidth: CGFloat
    let controlHeight: CGFloat
    let startDate: Date
    let shaderFrameInterval: Double
    let displayLevel: Double

    var body: some View {
        TimelineView(.animation(minimumInterval: shaderFrameInterval, paused: false)) { timeline in
            let elapsed = timeline.date.timeIntervalSince(startDate)
            
            let effectiveLevel: Double = {
                if case .processing = state {
                    return 0.28 + 0.10 * sin(elapsed * 1.7) + 0.05 * sin(elapsed * 3.9)
                } else {
                    return displayLevel
                }
            }()
            
            let colors = currentShaderColors(elapsed: elapsed, effectiveLevel: effectiveLevel)
            
            Capsule().fill(.white)
                .colorEffect(
                    ShaderLibrary.cloudOrbGlassWide(
                        .float2(mainWidth, controlHeight),
                        .float(elapsed),
                        .float(effectiveLevel),
                        .color(colors.top),
                        .color(colors.mid),
                        .color(colors.low)
                    )
                )
                .frame(width: mainWidth, height: controlHeight)
                .allowsHitTesting(false)
        }
    }

    private func currentShaderColors(elapsed: Double, effectiveLevel: Double) -> (top: Color, mid: Color, low: Color) {
        let talk = min(max(effectiveLevel, 0.0), 1.0)
        let breath = talk * talk * (3.0 - 2.0 * talk)
        
        let injection: Double
        let targetTop: (Double, Double, Double)
        let targetMid: (Double, Double, Double)
        let targetLow: (Double, Double, Double)

        switch state {
        case .processing:
            injection = 0.5 + 0.5 * breath
            targetTop = MacDictationPanelConstants.Colors.topProcessing
            targetMid = MacDictationPanelConstants.Colors.midProcessing
            targetLow = MacDictationPanelConstants.Colors.lowProcessing
        case .starting, .listening:
            injection = breath
            targetTop = MacDictationPanelConstants.Colors.topSpeaking
            targetMid = MacDictationPanelConstants.Colors.midSpeaking
            targetLow = MacDictationPanelConstants.Colors.lowSpeaking
        case .result(_):
            injection = 0.4
            targetTop = MacDictationPanelConstants.Colors.topSpeaking
            targetMid = MacDictationPanelConstants.Colors.midSpeaking
            targetLow = MacDictationPanelConstants.Colors.lowSpeaking
        default:
            injection = 0
            targetTop = MacDictationPanelConstants.Colors.topIdle
            targetMid = MacDictationPanelConstants.Colors.midIdle
            targetLow = MacDictationPanelConstants.Colors.lowIdle
        }

        let top = Color(
            red:   lerp(MacDictationPanelConstants.Colors.topIdle.0, targetTop.0, injection),
            green: lerp(MacDictationPanelConstants.Colors.topIdle.1, targetTop.1, injection),
            blue:  lerp(MacDictationPanelConstants.Colors.topIdle.2, targetTop.2, injection)
        )
        let mid = Color(
            red:   lerp(MacDictationPanelConstants.Colors.midIdle.0, targetMid.0, injection),
            green: lerp(MacDictationPanelConstants.Colors.midIdle.1, targetMid.1, injection),
            blue:  lerp(MacDictationPanelConstants.Colors.midIdle.2, targetMid.2, injection)
        )
        let low = Color(
            red:   lerp(MacDictationPanelConstants.Colors.lowIdle.0, targetLow.0, injection),
            green: lerp(MacDictationPanelConstants.Colors.lowIdle.1, targetLow.1, injection),
            blue:  lerp(MacDictationPanelConstants.Colors.lowIdle.2, targetLow.2, injection)
        )
        return (top, mid, low)
    }

    private func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }
}
#endif
