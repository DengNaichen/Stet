import MetalKit
import SwiftUI
import simd

enum DictationLevelShaderSignalMapper {
    static func signals(level: Double) -> MacDictationCapsuleVisualSignals {
        let clampedLevel = min(max(level, 0), 1)
        return MacDictationCapsuleVisualSignals(
            body: clampedLevel,
            presence: clampedLevel * 0.85,
            pulse: clampedLevel * 0.70,
            articulation: clampedLevel * 0.55
        )
    }
}

public struct DictationLevelShaderView: View {
    private let level: Double
    private let diameter: CGFloat
    private let preferredFramesPerSecond: Int
    private let isPaused: Bool
    private let theme: MacDictationShaderTheme

    @State private var startDate = Date()

    public init(
        level: Double,
        diameter: CGFloat,
        preferredFramesPerSecond: Int,
        isPaused: Bool,
        theme: MacDictationShaderTheme = .egg
    ) {
        self.level = level
        self.diameter = diameter
        self.preferredFramesPerSecond = preferredFramesPerSecond
        self.isPaused = isPaused
        self.theme = theme
    }

    public var body: some View {
        DictationLevelMetalEffectView(configuration: configuration)
            .frame(width: diameter, height: diameter)
            .clipShape(Circle())
    }

    private var configuration: DictationMetalEffectConfiguration {
        DictationMetalEffectConfiguration(
            size: CGSize(width: diameter, height: diameter),
            startDate: startDate,
            frameInterval: 1.0 / Double(max(preferredFramesPerSecond, 1)),
            signals: DictationLevelShaderSignalMapper.signals(level: level),
            colors: Self.colors(for: theme),
            isPaused: isPaused
        )
    }

    private static func colors(for theme: MacDictationShaderTheme) -> (
        cottonFoam: SIMD3<Float>,
        waveTop: SIMD3<Float>,
        deepSea: SIMD3<Float>
    ) {
        let palette = theme.palette.speaking
        let colorA = simdColor(palette.a)
        let colorB = simdColor(palette.b)
        let colorC = simdColor(palette.c)
        return (
            cottonFoam: colorA + (SIMD3<Float>(repeating: 1) - colorA) * 0.28,
            waveTop: colorB,
            deepSea: colorC * 0.86
        )
    }

    private static func simdColor(
        _ components: (Double, Double, Double)
    ) -> SIMD3<Float> {
        SIMD3(Float(components.0), Float(components.1), Float(components.2))
    }
}

#if os(macOS)
    private struct DictationLevelMetalEffectView: NSViewRepresentable {
        let configuration: DictationMetalEffectConfiguration

        func makeCoordinator() -> DictationMetalEffectCoordinator {
            DictationMetalEffectCoordinator()
        }

        func makeNSView(context: Context) -> MTKView {
            let view = context.coordinator.makeView()
            context.coordinator.update(view: view, configuration: configuration)
            return view
        }

        func updateNSView(_ nsView: MTKView, context: Context) {
            context.coordinator.update(view: nsView, configuration: configuration)
        }

        static func dismantleNSView(_ nsView: MTKView, coordinator: DictationMetalEffectCoordinator) {
            coordinator.dismantle(view: nsView)
        }
    }
#elseif os(iOS)
    private struct DictationLevelMetalEffectView: UIViewRepresentable {
        let configuration: DictationMetalEffectConfiguration

        func makeCoordinator() -> DictationMetalEffectCoordinator {
            DictationMetalEffectCoordinator()
        }

        func makeUIView(context: Context) -> MTKView {
            let view = context.coordinator.makeView()
            context.coordinator.update(view: view, configuration: configuration)
            return view
        }

        func updateUIView(_ uiView: MTKView, context: Context) {
            context.coordinator.update(view: uiView, configuration: configuration)
        }

        static func dismantleUIView(_ uiView: MTKView, coordinator: DictationMetalEffectCoordinator) {
            coordinator.dismantle(view: uiView)
        }
    }
#endif
