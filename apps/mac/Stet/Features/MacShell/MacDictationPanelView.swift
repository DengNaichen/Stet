#if os(macOS)
import SwiftUI

struct MacDictationPanelView: View {
    @EnvironmentObject private var appModel: MacAppModel

    let layout: MacDictationPanelLayout

    var body: some View {
        Group {
            switch appModel.dictationViewModel.state {
            case .idle:
                idleCapsule
            case .listening:
                recordingCapsule
            case .processing:
                thinkingCapsule
            case .result:
                insertedCapsule
            case .error(let message):
                errorCapsule(message: message)
            }
        }
        .frame(width: layout.panelSize.width, height: layout.panelSize.height)
    }

    private var idleCapsule: some View {
        shell(style: .idle) {
            HStack(spacing: 12) {
                controlButton(
                    systemName: "xmark",
                    isEmphasized: false,
                    action: appModel.hidePanel
                )

                Text("Ready")
                    .font(statusFont(weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                    .frame(maxWidth: .infinity)

                controlButton(
                    systemName: "mic.fill",
                    isEmphasized: true,
                    action: appModel.performPrimaryAction
                )
            }
        }
    }

    private var recordingCapsule: some View {
        shell(style: .listening(level: normalizedRecordingLevel)) {
            HStack(spacing: 14) {
                controlButton(
                    systemName: "xmark",
                    isEmphasized: false,
                    action: appModel.cancelActiveCapture
                )

                VoiceLevelBarsView(level: normalizedRecordingLevel, layout: layout)
                    .frame(maxWidth: .infinity)

                controlButton(
                    systemName: "checkmark",
                    isEmphasized: true,
                    action: appModel.performPrimaryAction
                )
            }
        }
    }

    private var thinkingCapsule: some View {
        shell(style: .processing) {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)

                Text(appModel.statusText)
                    .font(statusFont(weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var insertedCapsule: some View {
        shell(style: .result) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.white)

                Text(appModel.statusText)
                    .font(statusFont(weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func errorCapsule(message: String) -> some View {
        shell(style: .error) {
            HStack(spacing: 12) {
                controlButton(
                    systemName: "xmark",
                    isEmphasized: false,
                    action: appModel.hidePanel
                )

                Text(message)
                    .font(.system(size: layout.secondaryFontSize, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                controlButton(
                    systemName: "arrow.clockwise",
                    isEmphasized: true,
                    action: appModel.performPrimaryAction
                )
            }
        }
    }

    private func shell<Content: View>(
        style: LiquidCapsuleStyle,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, layout.horizontalPadding)
            .padding(.vertical, layout.verticalPadding)
            .frame(width: layout.capsuleSize.width, height: layout.capsuleSize.height)
            .background(
                ReactiveLiquidCapsuleBackground(
                    level: style.level,
                    isActive: style.isActive,
                    palette: style.palette
                )
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var normalizedRecordingLevel: Double {
        min(max(appModel.recordingLevel, 0), 1)
    }

    private func controlButton(
        systemName: String,
        isEmphasized: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: layout.controlSymbolSize, weight: .bold))
                .foregroundStyle(isEmphasized ? .black : .white)
                .frame(width: layout.controlButtonSize, height: layout.controlButtonSize)
                .background(
                    Circle()
                        .fill(isEmphasized ? Color.white : Color.white.opacity(0.12))
                )
        }
        .buttonStyle(.plain)
    }

    private func statusFont(weight: Font.Weight) -> Font {
        .system(size: layout.statusFontSize, weight: weight, design: .rounded)
    }
}

private struct ReactiveLiquidCapsuleBackground: View {
    let level: Double
    let isActive: Bool
    let palette: [Color]

    private var energy: Double {
        min(max(level, 0), 1)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isActive)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate

            ZStack {
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.76),
                                Color.black.opacity(0.92)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                LiquidColorField(time: time, level: energy, palette: palette)
                    .mask(
                        LiquidMetaballMask(time: time, level: energy)
                            .padding(-18)
                    )
                    .clipShape(Capsule(style: .continuous))
                    .opacity(0.97)

                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.18 + 0.10 * energy),
                                Color.white.opacity(0.05),
                                .clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .blendMode(.screen)

                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.02),
                                Color.black.opacity(0.16)
                            ],
                            startPoint: .center,
                            endPoint: .bottom
                        )
                    )

                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
            }
            .compositingGroup()
            .scaleEffect(CGFloat(1.0 + (isActive ? 0.014 * energy : 0)))
            .shadow(
                color: Color.white.opacity(0.04 + 0.10 * energy),
                radius: CGFloat(10 + 14 * energy),
                y: 2
            )
        }
    }
}

private struct LiquidColorField: View {
    let time: TimeInterval
    let level: Double
    let palette: [Color]

    var body: some View {
        GeometryReader { proxy in
            let bubbles = LiquidBubble.colorBubbles(
                in: proxy.size,
                time: time,
                level: level,
                palette: palette
            )

            ZStack {
                ForEach(bubbles) { bubble in
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    bubble.color.opacity(0.98),
                                    bubble.color.opacity(0.62),
                                    bubble.color.opacity(0.16),
                                    .clear
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: bubble.radius * 1.15
                            )
                        )
                        .frame(width: bubble.radius * 2.3, height: bubble.radius * 2.3)
                        .position(x: bubble.center.x, y: bubble.center.y)
                        .blendMode(.plusLighter)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .blur(radius: CGFloat(22 + level * 16), opaque: false)
            .saturation(1.2 + level * 0.6)
        }
        .compositingGroup()
    }
}

private struct LiquidMetaballMask: View {
    let time: TimeInterval
    let level: Double

    var body: some View {
        GeometryReader { proxy in
            let bubbles = LiquidBubble.maskBubbles(
                in: proxy.size,
                time: time,
                level: level
            )

            ZStack {
                ForEach(bubbles) { bubble in
                    Circle()
                        .fill(Color.white)
                        .frame(width: bubble.radius * 2.0, height: bubble.radius * 2.0)
                        .position(x: bubble.center.x, y: bubble.center.y)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .blur(radius: CGFloat(18 + level * 16), opaque: false)
            .contrast(14 + level * 10)
            .saturation(0)
        }
        .compositingGroup()
    }
}

private struct LiquidBubble: Identifiable {
    let id: Int
    let center: CGPoint
    let radius: CGFloat
    let color: Color

    static func colorBubbles(
        in size: CGSize,
        time: TimeInterval,
        level: Double,
        palette: [Color]
    ) -> [LiquidBubble] {
        let energy = CGFloat(min(max(level, 0), 1))
        let width = size.width
        let height = size.height
        let anchors: [(CGFloat, CGFloat)] = [
            (0.10, 0.32),
            (0.28, 0.72),
            (0.46, 0.34),
            (0.68, 0.66),
            (0.86, 0.38)
        ]

        let baseRadius = max(height * 0.72, min(width * 0.22, height * 1.05))

        return anchors.enumerated().map { index, anchor in
            let phase = Double(index) * 1.37
            let xSwing = width * (0.05 + 0.09 * energy) * CGFloat(sin(time * (0.55 + Double(index) * 0.08) + phase))
            let ySwing = height * (0.10 + 0.10 * energy) * CGFloat(cos(time * (0.74 + Double(index) * 0.06) + phase * 1.2))
            let pulse = 0.5 + 0.5 * CGFloat(sin(time * (1.05 + Double(index) * 0.09) + phase * 0.7))
            let radius = baseRadius + height * (0.08 + 0.16 * energy) * pulse

            return LiquidBubble(
                id: index,
                center: CGPoint(
                    x: width * anchor.0 + xSwing,
                    y: height * anchor.1 + ySwing
                ),
                radius: radius,
                color: palette[index % palette.count]
            )
        }
    }

    static func maskBubbles(
        in size: CGSize,
        time: TimeInterval,
        level: Double
    ) -> [LiquidBubble] {
        let energy = CGFloat(min(max(level, 0), 1))
        let width = size.width
        let height = size.height
        let anchors: [CGFloat] = [0.07, 0.22, 0.36, 0.50, 0.64, 0.78, 0.93]

        return anchors.enumerated().map { index, anchor in
            let phase = Double(index) * 0.73
            let xSwing = width * 0.028 * CGFloat(sin(time * (0.95 + Double(index) * 0.07) + phase))
            let ySwing = height * (0.05 + 0.12 * energy) * CGFloat(cos(time * (1.35 + Double(index) * 0.08) + phase * 1.4))
            let base = height * (0.40 + 0.03 * CGFloat(index % 2))
            let pulse = height * (0.08 + 0.16 * energy) * (0.5 + 0.5 * CGFloat(sin(time * (1.75 + Double(index) * 0.10) + phase * 1.3)))

            return LiquidBubble(
                id: index,
                center: CGPoint(
                    x: width * anchor + xSwing,
                    y: height * 0.50 + ySwing
                ),
                radius: base + pulse,
                color: .white
            )
        }
    }
}

private struct LiquidCapsuleStyle {
    let level: Double
    let isActive: Bool
    let palette: [Color]

    static let idle = LiquidCapsuleStyle(
        level: 0.10,
        isActive: false,
        palette: LiquidPalette.idle
    )

    static func listening(level: Double) -> LiquidCapsuleStyle {
        LiquidCapsuleStyle(
            level: max(0.12, min(max(level, 0), 1)),
            isActive: true,
            palette: LiquidPalette.listening
        )
    }

    static let processing = LiquidCapsuleStyle(
        level: 0.30,
        isActive: true,
        palette: LiquidPalette.processing
    )

    static let result = LiquidCapsuleStyle(
        level: 0.18,
        isActive: false,
        palette: LiquidPalette.result
    )

    static let error = LiquidCapsuleStyle(
        level: 0.20,
        isActive: false,
        palette: LiquidPalette.error
    )
}

private enum LiquidPalette {
    static let idle: [Color] = [
        Color(red: 0.36, green: 0.82, blue: 1.00),
        Color(red: 0.46, green: 0.54, blue: 1.00),
        Color(red: 0.86, green: 0.46, blue: 1.00),
        Color(red: 0.50, green: 1.00, blue: 0.82)
    ]

    static let listening: [Color] = [
        Color(red: 0.34, green: 0.92, blue: 1.00),
        Color(red: 0.44, green: 0.52, blue: 1.00),
        Color(red: 1.00, green: 0.42, blue: 0.82),
        Color(red: 0.60, green: 1.00, blue: 0.72),
        Color(red: 1.00, green: 0.74, blue: 0.32)
    ]

    static let processing: [Color] = [
        Color(red: 0.30, green: 0.82, blue: 1.00),
        Color(red: 0.52, green: 0.40, blue: 1.00),
        Color(red: 0.92, green: 0.50, blue: 1.00),
        Color(red: 0.42, green: 0.98, blue: 0.90)
    ]

    static let result: [Color] = [
        Color(red: 0.30, green: 0.94, blue: 0.78),
        Color(red: 0.28, green: 0.78, blue: 1.00),
        Color(red: 0.72, green: 1.00, blue: 0.54),
        Color(red: 0.98, green: 0.84, blue: 0.40)
    ]

    static let error: [Color] = [
        Color(red: 1.00, green: 0.44, blue: 0.48),
        Color(red: 1.00, green: 0.56, blue: 0.78),
        Color(red: 0.98, green: 0.66, blue: 0.36),
        Color(red: 0.66, green: 0.44, blue: 1.00)
    ]
}

private struct VoiceLevelBarsView: View {
    let level: Double
    let layout: MacDictationPanelLayout

    private let multipliers: [CGFloat] = [0.35, 0.5, 0.72, 0.9, 1, 0.9, 0.72, 0.5, 0.35]

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            ForEach(Array(multipliers.enumerated()), id: \.offset) { _, multiplier in
                Capsule()
                    .fill(Color.white)
                    .frame(width: 4, height: barHeight(multiplier: multiplier))
            }
        }
        .frame(height: layout.voiceBarHeight)
        .animation(.spring(response: 0.18, dampingFraction: 0.72), value: level)
    }

    private func barHeight(multiplier: CGFloat) -> CGFloat {
        let baseHeight: CGFloat = 5
        let variableHeight = CGFloat(max(level, 0.08)) * (layout.voiceBarHeight - baseHeight) * multiplier
        return baseHeight + variableHeight
    }
}
#endif
