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

    @State private var startDate = Date()

    public init(
        level: Double,
        diameter: CGFloat,
        preferredFramesPerSecond: Int,
        isPaused: Bool
    ) {
        self.level = level
        self.diameter = diameter
        self.preferredFramesPerSecond = preferredFramesPerSecond
        self.isPaused = isPaused
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
            colors: Self.eggSpeakingColors,
            isPaused: isPaused,
            motionGain: 1.55
        )
    }

    private static let eggSpeakingColors:
        (
            cottonFoam: SIMD3<Float>,
            waveTop: SIMD3<Float>,
            deepSea: SIMD3<Float>
        ) = {
            let shell = SIMD3<Float>(202.0 / 255.0, 202.0 / 255.0, 191.0 / 255.0)
            let sky = SIMD3<Float>(94.0 / 255.0, 141.0 / 255.0, 167.0 / 255.0)
            let yolk = SIMD3<Float>(220.0 / 255.0, 152.0 / 255.0, 3.0 / 255.0)
            return (
                cottonFoam: shell + (SIMD3<Float>(repeating: 1) - shell) * 0.28,
                waveTop: sky,
                deepSea: yolk * 0.86
            )
        }()
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
