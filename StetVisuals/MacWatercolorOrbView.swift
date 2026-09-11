#if os(macOS)
    import Metal
    import SwiftUI

    private final class WatercolorShaderBundle: NSObject {}

    struct MacWatercolorOrbPaint: View {
        private static let hasMetal = MTLCreateSystemDefaultDevice() != nil
        let frame: MacWatercolorOrbFrame
        let theme: MacDictationShaderTheme

        private var palette: MacWatercolorOrbPalette { MacWatercolorOrbPalette(theme: theme) }

        var body: some View {
            Group {
                if Self.hasMetal {
                    Circle().fill(.white)
                        .colorEffect(
                            ShaderLibrary.bundle(Bundle(for: WatercolorShaderBundle.self)).stetWatercolorOrb(
                                .float2(64, 64),
                                .float(Float(frame.phase)),
                                .float(Float(frame.anchor)),
                                .float(Float(frame.motion)),
                                .float(Float(frame.tone)),
                                .float(Float(MacWatercolorOrbPreset.weave)),
                                .float(Float(MacWatercolorOrbPreset.grain)),
                                .float3(Float(frame.idleWave.x), Float(frame.idleWave.y), Float(frame.idleWave.z)),
                                shaderColor(palette.groundLow), shaderColor(palette.groundHigh),
                                shaderColor(palette.interlayer), shaderColor(palette.lightPigment),
                                shaderColor(palette.pigment), shaderColor(palette.densePigment)
                            )
                        )
                } else {
                    Circle().fill(
                        LinearGradient(
                            colors: [palette.groundHigh, palette.interlayer, palette.lightPigment, palette.pigment]
                                .map { Color(red: Double($0.x), green: Double($0.y), blue: Double($0.z)) },
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                }
            }
            .frame(width: 64, height: 64)
            // Scaling the complete paint preserves the approved granule size during Thinking.
            .scaleEffect(frame.scale)
            .allowsHitTesting(false)
        }

        private func shaderColor(_ color: SIMD3<Float>) -> Shader.Argument {
            .float3(color.x, color.y, color.z)
        }
    }

    struct MacWatercolorOrbView: View {
        let model: MacDictationCapsuleVisualModel
        let actions: MacDictationCapsuleVisualActions

        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Namespace private var glassNamespace
        @State private var motion = MacWatercolorOrbMotion()
        @State private var presentation = MacWatercolorOrbPresentation()
        @State private var previousDate: Date?

        var body: some View {
            TimelineView(
                .animation(
                    minimumInterval: MacWatercolorOrbPreset.frameInterval,
                    paused: reduceMotion || (!motion.isVisible && !presentation.isAnimating(at: .now))
                )
            ) { context in
                let progress = presentation.progress(at: context.date)
                ZStack {
                    MacDictationGlassContainer(spacing: MacWatercolorOrbLayout.glassSpacing) {
                        ZStack {
                            glassButton("xmark", label: "Cancel dictation", id: "cancel", side: -1, progress: progress)
                            {
                                actions.onDismiss()
                            }
                            glassButton(
                                "checkmark", label: "Finish dictation", id: "confirm", side: 1, progress: progress
                            ) {
                                actions.onConfirm()
                            }
                            .disabled(model.state == .processing)

                            Color.clear
                                .frame(width: motion.frame.diameter, height: motion.frame.diameter)
                                .stetGlassEffect(in: Circle())
                                .stetGlassID("main", in: glassNamespace)
                                .allowsHitTesting(false)
                        }
                    }
                    MacWatercolorOrbPaint(frame: motion.frame, theme: model.shaderTheme)
                        .accessibilityLabel(statusLabel)
                        .accessibilityIdentifier("dictation.watercolorOrb")
                }
                .opacity(min(1, progress * 3))
                .frame(width: model.panelSize.width, height: model.panelSize.height)
                .accessibilityHidden(!motion.isVisible)
                .onChange(of: context.date) { _, date in
                    if let previousDate {
                        motion.advance(
                            by: date.timeIntervalSince(previousDate),
                            level: MacWatercolorOrbMotion.voiceLevel(for: model.signals)
                        )
                    }
                    previousDate = date
                }
            }
            .onAppear { synchronize() }
            .onChange(of: model.state) { _, _ in synchronize() }
            .onChange(of: reduceMotion) { _, _ in synchronize() }
            .onDisappear {
                previousDate = nil
                motion.setState(.hidden)
                presentation.setVisible(false, at: .now, reduceMotion: true)
            }
        }

        private var statusLabel: String {
            switch model.state {
            case .processing: "Thinking"
            case .starting: "Starting microphone"
            default: "Listening"
            }
        }

        private func synchronize() {
            motion.setState(model.state, reduceMotion: reduceMotion)
            presentation.setVisible(motion.isVisible, at: .now, reduceMotion: reduceMotion)
            previousDate = nil
        }

        private func glassButton(
            _ symbol: String, label: String, id: String, side: Double, progress: Double,
            action: @escaping () -> Void
        ) -> some View {
            let point = MacWatercolorOrbLayout.buttonPosition(progress: progress, side: side)
            return Button(action: action) {
                Image(systemName: symbol)
                    .font(.system(size: 12 * motion.frame.scale, weight: .semibold))
                    .foregroundStyle(.primary)
                    .opacity(min(1, max(0, (progress - 0.18) / 0.35)))
                    .frame(width: motion.frame.buttonDiameter, height: motion.frame.buttonDiameter)
                    .stetInteractiveGlassEffect(in: Circle())
                    .stetGlassID(id, in: glassNamespace)
                    .padding((MacWatercolorOrbLayout.hitDiameter - motion.frame.buttonDiameter) / 2)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .offset(x: point.x, y: point.y)
            .allowsHitTesting(motion.isVisible && progress > 0.98)
            .accessibilityHidden(!motion.isVisible || progress <= 0.98)
            .accessibilityLabel(label)
            .accessibilityIdentifier("dictation.\(id)")
            .help(label)
        }
    }

    /// Uses the same material and silence behavior in appearance settings, without session controls.
    struct MacWatercolorOrbPreview: View {
        let theme: MacDictationShaderTheme
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var motion = MacWatercolorOrbMotion()
        @State private var previousDate: Date?

        var body: some View {
            TimelineView(.animation(minimumInterval: MacWatercolorOrbPreset.frameInterval, paused: reduceMotion)) {
                context in
                MacWatercolorOrbPaint(frame: motion.frame, theme: theme)
                    .onChange(of: context.date) { _, date in
                        if let previousDate { motion.advance(by: date.timeIntervalSince(previousDate), level: 0) }
                        previousDate = date
                    }
            }
            .onAppear { motion.setState(.listening, reduceMotion: reduceMotion) }
            .onChange(of: reduceMotion) { _, value in
                motion.setState(.listening, reduceMotion: value)
                previousDate = nil
            }
            .onDisappear { previousDate = nil }
            .accessibilityLabel("\(theme.title) preview")
        }
    }
#endif
