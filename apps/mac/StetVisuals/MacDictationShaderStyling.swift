#if os(macOS)
import SwiftUI

enum MacDictationShaderStyling {
    static func detail(
        for state: MacDictationCapsuleVisualState,
        signals: MacDictationCapsuleVisualSignals
    ) -> Double {
        let sustained = eased(signals.body)
        let edge = max(signals.pulse, signals.articulation)

        switch state {
        case .starting:
            return min(0.86, 0.56 + sustained * 0.18 + edge * 0.10)
        case .listening:
            return min(1.0, 0.76 + signals.articulation * 0.16 + signals.pulse * 0.08)
        case .processing:
            return 0.92
        default:
            return 0.52
        }
    }

    static func colors(
        for state: MacDictationCapsuleVisualState,
        elapsed: Double,
        signals: MacDictationCapsuleVisualSignals
    ) -> (top: Color, mid: Color, low: Color) {
        let sustained = eased(max(signals.body, signals.presence * 0.92))
        let accent = eased(max(signals.pulse, signals.articulation * 0.68))

        let baseTop: (Double, Double, Double)
        let baseMid: (Double, Double, Double)
        let baseLow: (Double, Double, Double)
        let injection: Double
        let targetTop: (Double, Double, Double)
        let targetMid: (Double, Double, Double)
        let targetLow: (Double, Double, Double)

        switch state {
        case .processing:
            baseTop = MacDictationPanelConstants.Colors.topIdle
            baseMid = MacDictationPanelConstants.Colors.midIdle
            baseLow = MacDictationPanelConstants.Colors.lowIdle
            injection = min(1, 0.46 + sustained * 0.32 + accent * 0.22)
            targetTop = MacDictationPanelConstants.Colors.topProcessing
            targetMid = MacDictationPanelConstants.Colors.midProcessing
            targetLow = MacDictationPanelConstants.Colors.lowProcessing
        case .starting:
            baseTop = MacDictationPanelConstants.Colors.topStarting
            baseMid = MacDictationPanelConstants.Colors.midStarting
            baseLow = MacDictationPanelConstants.Colors.lowStarting
            injection = min(1, 0.28 + sustained * 0.18 + accent * 0.10)
            targetTop = MacDictationPanelConstants.Colors.topStarting
            targetMid = MacDictationPanelConstants.Colors.midStarting
            targetLow = MacDictationPanelConstants.Colors.lowStarting
        case .listening:
            baseTop = MacDictationPanelConstants.Colors.topIdle
            baseMid = MacDictationPanelConstants.Colors.midIdle
            baseLow = MacDictationPanelConstants.Colors.lowIdle
            injection = min(1, 0.12 + sustained * 0.68 + accent * 0.20)
            targetTop = MacDictationPanelConstants.Colors.topSpeaking
            targetMid = MacDictationPanelConstants.Colors.midSpeaking
            targetLow = MacDictationPanelConstants.Colors.lowSpeaking
        case .result:
            baseTop = MacDictationPanelConstants.Colors.topIdle
            baseMid = MacDictationPanelConstants.Colors.midIdle
            baseLow = MacDictationPanelConstants.Colors.lowIdle
            injection = 0.4
            targetTop = MacDictationPanelConstants.Colors.topSpeaking
            targetMid = MacDictationPanelConstants.Colors.midSpeaking
            targetLow = MacDictationPanelConstants.Colors.lowSpeaking
        default:
            baseTop = MacDictationPanelConstants.Colors.topIdle
            baseMid = MacDictationPanelConstants.Colors.midIdle
            baseLow = MacDictationPanelConstants.Colors.lowIdle
            injection = 0
            targetTop = MacDictationPanelConstants.Colors.topIdle
            targetMid = MacDictationPanelConstants.Colors.midIdle
            targetLow = MacDictationPanelConstants.Colors.lowIdle
        }

        let top = Color(
            red: lerp(baseTop.0, targetTop.0, injection),
            green: lerp(baseTop.1, targetTop.1, injection),
            blue: lerp(baseTop.2, targetTop.2, injection)
        )
        let mid = Color(
            red: lerp(baseMid.0, targetMid.0, injection),
            green: lerp(baseMid.1, targetMid.1, injection),
            blue: lerp(baseMid.2, targetMid.2, injection)
        )
        let low = Color(
            red: lerp(baseLow.0, targetLow.0, injection),
            green: lerp(baseLow.1, targetLow.1, injection),
            blue: lerp(baseLow.2, targetLow.2, injection)
        )
        return (top, mid, low)
    }

    private static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }

    private static func eased(_ value: Double) -> Double {
        let clamped = min(max(value, 0), 1)
        return clamped * clamped * (3 - 2 * clamped)
    }
}
#endif
