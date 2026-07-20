#if os(macOS)
    import AppKit
    import SwiftUI

    enum MacDictationShaderStyling {
        static func colors(
            for state: MacDictationCapsuleVisualState,
            theme: MacDictationShaderTheme,
            elapsed: Double
        ) -> (a: Color, b: Color, c: Color) {
            let palette = theme.palette

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

        static func orbColors(
            for state: MacDictationCapsuleVisualState,
            theme: MacDictationShaderTheme,
            elapsed: Double
        ) -> (cottonFoam: Color, waveTop: Color, deepSea: Color) {
            let palette = colors(for: state, theme: theme, elapsed: elapsed)
            return (
                cottonFoam: lifted(palette.a, toward: .white, amount: 0.28),
                waveTop: palette.b,
                deepSea: deepened(palette.c, amount: 0.14)
            )
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

        private static func lifted(_ color: Color, toward target: Color, amount: Double) -> Color {
            blend(color, target, amount: amount)
        }

        private static func deepened(_ color: Color, amount: Double) -> Color {
            blend(color, .black, amount: amount)
        }

        private static func blend(_ source: Color, _ target: Color, amount: Double) -> Color {
            let sourceColor = NSColor(source).usingColorSpace(.deviceRGB) ?? .white
            let targetColor = NSColor(target).usingColorSpace(.deviceRGB) ?? .white
            let clamped = min(max(amount, 0), 1)
            return Color(
                red: sourceColor.redComponent + (targetColor.redComponent - sourceColor.redComponent) * clamped,
                green: sourceColor.greenComponent + (targetColor.greenComponent - sourceColor.greenComponent) * clamped,
                blue: sourceColor.blueComponent + (targetColor.blueComponent - sourceColor.blueComponent) * clamped
            )
        }
    }
#endif
