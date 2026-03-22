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
        theme: MacDictationShaderTheme,
        elapsed: Double,
        signals: MacDictationCapsuleVisualSignals
    ) -> (top: Color, mid: Color, low: Color) {
        let palette = theme.palette
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
            baseTop = palette.idle.top
            baseMid = palette.idle.mid
            baseLow = palette.idle.low
            injection = min(1, 0.46 + sustained * 0.32 + accent * 0.22)
            targetTop = palette.processing.top
            targetMid = palette.processing.mid
            targetLow = palette.processing.low
        case .starting:
            baseTop = palette.starting.top
            baseMid = palette.starting.mid
            baseLow = palette.starting.low
            injection = min(1, 0.28 + sustained * 0.18 + accent * 0.10)
            targetTop = palette.starting.top
            targetMid = palette.starting.mid
            targetLow = palette.starting.low
        case .listening:
            baseTop = palette.idle.top
            baseMid = palette.idle.mid
            baseLow = palette.idle.low
            injection = min(1, 0.12 + sustained * 0.68 + accent * 0.20)
            targetTop = palette.speaking.top
            targetMid = palette.speaking.mid
            targetLow = palette.speaking.low
        case .result:
            baseTop = palette.idle.top
            baseMid = palette.idle.mid
            baseLow = palette.idle.low
            injection = 0.4
            targetTop = palette.speaking.top
            targetMid = palette.speaking.mid
            targetLow = palette.speaking.low
        default:
            baseTop = palette.idle.top
            baseMid = palette.idle.mid
            baseLow = palette.idle.low
            injection = 0
            targetTop = palette.idle.top
            targetMid = palette.idle.mid
            targetLow = palette.idle.low
        }

        let top = color(
            from: (
                lerp(baseTop.0, targetTop.0, injection),
                lerp(baseTop.1, targetTop.1, injection),
                lerp(baseTop.2, targetTop.2, injection)
            )
        )
        let mid = color(
            from: (
                lerp(baseMid.0, targetMid.0, injection),
                lerp(baseMid.1, targetMid.1, injection),
                lerp(baseMid.2, targetMid.2, injection)
            )
        )
        let low = color(
            from: (
                lerp(baseLow.0, targetLow.0, injection),
                lerp(baseLow.1, targetLow.1, injection),
                lerp(baseLow.2, targetLow.2, injection)
            )
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

    private static func color(from components: (Double, Double, Double)) -> Color {
        Color(red: components.0, green: components.1, blue: components.2)
    }
}
#endif
