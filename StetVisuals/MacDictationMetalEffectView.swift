#if os(macOS)
    import AppKit
    import MetalKit
    import SwiftUI
    import simd

    struct MacDictationMetalEffectView: NSViewRepresentable {
        let size: CGSize
        let startDate: Date
        let frameInterval: Double
        let signals: MacDictationCapsuleVisualSignals
        let colors: (cottonFoam: Color, waveTop: Color, deepSea: Color)
        let isPaused: Bool
        var fieldGain: Float = 1
        var fieldBlurSigma: Float = MacDictationAudioFieldConstants.fieldBlurSigma
        var gradientBlurSigma: Float = MacDictationAudioFieldConstants.gradientBlurSigma
        var motionGain: Float = 1
        var processingMix: Float = 0

        func makeCoordinator() -> DictationMetalEffectCoordinator {
            DictationMetalEffectCoordinator()
        }

        func makeNSView(context: Context) -> MTKView {
            let view = context.coordinator.makeView()
            update(view, coordinator: context.coordinator)
            return view
        }

        func updateNSView(_ nsView: MTKView, context: Context) {
            update(nsView, coordinator: context.coordinator)
        }

        static func dismantleNSView(_ nsView: MTKView, coordinator: DictationMetalEffectCoordinator) {
            coordinator.dismantle(view: nsView)
        }

        private func update(_ nsView: MTKView, coordinator: DictationMetalEffectCoordinator) {
            let configuration = DictationMetalEffectConfiguration(
                size: size,
                startDate: startDate,
                frameInterval: frameInterval,
                signals: signals,
                colors: (
                    cottonFoam: colors.cottonFoam.simdRGB,
                    waveTop: colors.waveTop.simdRGB,
                    deepSea: colors.deepSea.simdRGB
                ),
                isPaused: isPaused,
                fieldGain: fieldGain,
                fieldBlurSigma: fieldBlurSigma,
                gradientBlurSigma: gradientBlurSigma,
                motionGain: motionGain,
                processingMix: processingMix
            )
            coordinator.update(view: nsView, configuration: configuration)
        }
    }

    private extension Color {
        var simdRGB: SIMD3<Float> {
            let nsColor = NSColor(self).usingColorSpace(.deviceRGB) ?? .white
            return SIMD3<Float>(
                Float(nsColor.redComponent),
                Float(nsColor.greenComponent),
                Float(nsColor.blueComponent)
            )
        }
    }
#endif
