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
        ) -> (a: Color, b: Color, c: Color) {
            let palette = theme.palette

            // State-time driven transition instead of audio-driven injection.
            // The elapsed time since entering the state drives the crossfade,
            // not the instantaneous audio strength.
            let transitionSpeed = 0.35
            let stateProgress = min(1.0, elapsed * transitionSpeed)
            let injection = eased(stateProgress)

            let baseA: (Double, Double, Double)
            let baseB: (Double, Double, Double)
            let baseC: (Double, Double, Double)
            let targetA: (Double, Double, Double)
            let targetB: (Double, Double, Double)
            let targetC: (Double, Double, Double)

            switch state {
            case .processing:
                baseA = palette.idle.a
                baseB = palette.idle.b
                baseC = palette.idle.c
                targetA = palette.processing.a
                targetB = palette.processing.b
                targetC = palette.processing.c
            case .starting:
                baseA = palette.idle.a
                baseB = palette.idle.b
                baseC = palette.idle.c
                targetA = palette.starting.a
                targetB = palette.starting.b
                targetC = palette.starting.c
            case .listening:
                baseA = palette.idle.a
                baseB = palette.idle.b
                baseC = palette.idle.c
                targetA = palette.speaking.a
                targetB = palette.speaking.b
                targetC = palette.speaking.c
            case .result:
                baseA = palette.idle.a
                baseB = palette.idle.b
                baseC = palette.idle.c
                targetA = palette.speaking.a
                targetB = palette.speaking.b
                targetC = palette.speaking.c
            default:
                baseA = palette.idle.a
                baseB = palette.idle.b
                baseC = palette.idle.c
                targetA = palette.idle.a
                targetB = palette.idle.b
                targetC = palette.idle.c
            }

            let a = color(
                from: (
                    lerp(baseA.0, targetA.0, injection),
                    lerp(baseA.1, targetA.1, injection),
                    lerp(baseA.2, targetA.2, injection)
                )
            )
            let b = color(
                from: (
                    lerp(baseB.0, targetB.0, injection),
                    lerp(baseB.1, targetB.1, injection),
                    lerp(baseB.2, targetB.2, injection)
                )
            )
            let c = color(
                from: (
                    lerp(baseC.0, targetC.0, injection),
                    lerp(baseC.1, targetC.1, injection),
                    lerp(baseC.2, targetC.2, injection)
                )
            )
            return (a, b, c)
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
