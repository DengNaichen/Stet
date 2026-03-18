#if os(macOS)
import SwiftUI

struct MacDictationPanelView: View {
    @StateObject private var viewModel: MacDictationPanelViewModel

    let layout: MacDictationPanelLayout

    init(layout: MacDictationPanelLayout, appModel: MacAppModel) {
        self.layout = layout
        _viewModel = StateObject(wrappedValue: MacDictationPanelViewModel(appModel: appModel))
    }

    var body: some View {
        Group {
            switch viewModel.state {
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
            HStack(spacing: 10) {
                controlButton(
                    systemName: "xmark",
                    isEmphasized: false,
                    action: viewModel.hidePanel
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
                    action: viewModel.performPrimaryAction
                )
            }
        }
    }

    private var recordingCapsule: some View {
        shell(style: .listening(level: emphasizedRecordingLevel)) {
            HStack(spacing: 12) {
                controlButton(
                    systemName: "xmark",
                    isEmphasized: false,
                    action: viewModel.cancelActiveCapture
                )

                VoiceLevelBarsView(level: emphasizedRecordingLevel, layout: layout)
                    .frame(maxWidth: .infinity)

                controlButton(
                    systemName: "checkmark",
                    isEmphasized: true,
                    action: viewModel.performPrimaryAction
                )
            }
        }
    }

    private var thinkingCapsule: some View {
        shell(style: .processing) {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)

                Text(viewModel.statusText)
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

                Text(viewModel.statusText)
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
            HStack(spacing: 10) {
                controlButton(
                    systemName: "xmark",
                    isEmphasized: false,
                    action: viewModel.hidePanel
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
                    action: viewModel.performPrimaryAction
                )
            }
        }
    }

    private func shell<Content: View>(
        style: BlendCapsuleStyle,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, layout.horizontalPadding)
            .padding(.vertical, layout.verticalPadding)
            .frame(width: layout.capsuleSize.width, height: layout.capsuleSize.height)
            .background(
                ReactiveBlendCapsuleBackground(
                    level: style.level,
                    isActive: style.isActive,
                    palette: style.palette
                )
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var normalizedRecordingLevel: Double {
        min(max(viewModel.recordingLevel, 0), 1)
    }

    private var emphasizedRecordingLevel: Double {
        let silenceFloor = 0.08
        let normalized = normalizedRecordingLevel
        let lifted = max(normalized - silenceFloor, 0) / (1 - silenceFloor)
        let emphasized = pow(lifted, 0.58)
        return min(max(0.1 + emphasized * 0.9, 0.1), 1)
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

private struct ReactiveBlendCapsuleBackground: View {
    let level: Double
    let isActive: Bool
    let palette: [Color]

    private var energy: Double {
        min(max(level, 0), 1)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isActive)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let pulseScale = isActive ? (0.985 + 0.05 * energy) : 1
            let shadowRadius = 14 + 12 * energy
            let shadowYOffset = 6 + 5 * energy

            ZStack {
                Capsule(style: .continuous)
                    .fill(BlendPalette.surface)

                ColorCloudField(
                    time: time,
                    level: energy,
                    palette: palette,
                    isActive: isActive
                )
                .clipShape(Capsule(style: .continuous))

                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.16),
                                Color.white.opacity(0.05),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.clear,
                                Color.black.opacity(0.05)
                            ],
                            startPoint: .center,
                            endPoint: .bottom
                        )
                    )

                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
            }
            .scaleEffect(x: 1, y: pulseScale, anchor: .center)
            .clipShape(Capsule(style: .continuous))
            .shadow(color: Color.black.opacity(0.1 + 0.08 * energy), radius: shadowRadius, y: shadowYOffset)
            .animation(.interactiveSpring(response: 0.18, dampingFraction: 0.72), value: energy)
        }
    }
}

private struct ColorCloudField: View {
    let time: TimeInterval
    let level: Double
    let palette: [Color]
    let isActive: Bool

    var body: some View {
        GeometryReader { proxy in
            let blobs = BlendBlob.makeBlobs(
                in: proxy.size,
                time: time,
                level: level,
                palette: palette,
                isActive: isActive
            )

            ZStack {
                Rectangle()
                    .fill(BlendPalette.base)

                ForEach(blobs) { blob in
                    Ellipse()
                        .fill(blob.color.opacity(blob.opacity))
                        .frame(width: blob.size.width, height: blob.size.height)
                        .position(x: blob.center.x, y: blob.center.y)
                        .blur(radius: blob.blur)
                }

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.04 + 0.06 * level),
                                Color.clear,
                                Color.black.opacity(0.04)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .drawingGroup(opaque: true, colorMode: .linear)
            .saturation(1.08 + 0.2 * level)
            .brightness(0.012 + 0.04 * level)
        }
    }
}

private struct BlendBlob: Identifiable {
    let id: Int
    let center: CGPoint
    let size: CGSize
    let color: Color
    let blur: CGFloat
    let opacity: Double

    static func makeBlobs(
        in size: CGSize,
        time: TimeInterval,
        level: Double,
        palette: [Color],
        isActive: Bool
    ) -> [BlendBlob] {
        let energy = CGFloat(min(max(level, 0), 1))
        let motion = isActive ? (0.55 + 0.95 * energy) : 0.16
        let width = size.width
        let height = size.height

        let anchors: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (0.08, 0.22, 0.68, 1.28),
            (0.28, 0.74, 0.62, 1.12),
            (0.50, 0.34, 0.70, 1.30),
            (0.72, 0.68, 0.62, 1.08),
            (0.93, 0.28, 0.60, 1.02)
        ]

        return anchors.enumerated().map { index, anchor in
            let seed = Double(index) * 11.73 + 0.91

            let smoothX = width * (0.04 + 0.075 * motion) * smoothNoise(time, seed: seed)
            let smoothY = height * (0.06 + 0.1 * motion) * smoothNoise(time * 1.17, seed: seed + 3.2)

            let jumpX = width * (0.01 + 0.024 * motion) * steppedNoise(time * (4.4 + Double(level) * 10.0), seed: seed + 8.4)
            let jumpY = height * (0.012 + 0.03 * motion) * steppedNoise(time * (5.6 + Double(level) * 13.0), seed: seed + 14.7)

            let widthPulse = 1 + (0.06 + 0.18 * motion) * smoothNoise(time * (1.05 + Double(index) * 0.08), seed: seed + 1.6)
            let heightPulse = 1 + (0.05 + 0.16 * motion) * smoothNoise(time * (0.92 + Double(index) * 0.07), seed: seed + 4.9)

            return BlendBlob(
                id: index,
                center: CGPoint(
                    x: width * anchor.0 + smoothX + jumpX,
                    y: height * anchor.1 + smoothY + jumpY
                ),
                size: CGSize(
                    width: width * anchor.2 * widthPulse,
                    height: height * anchor.3 * heightPulse
                ),
                color: palette[index % palette.count],
                blur: height * (0.24 + 0.06 * motion),
                opacity: Double(0.48 + 0.24 * motion + 0.05 * CGFloat(index % 2))
            )
        }
    }

    private static func smoothNoise(_ t: TimeInterval, seed: Double) -> CGFloat {
        let value =
            0.62 * sin(t * 0.82 + seed) +
            0.26 * sin(t * 1.47 + seed * 1.31) +
            0.12 * cos(t * 2.21 + seed * 0.73)
        return CGFloat(value)
    }

    private static func steppedNoise(_ t: TimeInterval, seed: Double) -> CGFloat {
        let step = floor(t)
        let raw = sin((step + seed) * 12.9898) * 43758.5453
        let fractional = raw - floor(raw)
        return CGFloat(fractional * 2 - 1)
    }
}

private struct BlendCapsuleStyle {
    let level: Double
    let isActive: Bool
    let palette: [Color]

    static let idle = BlendCapsuleStyle(
        level: 0.10,
        isActive: false,
        palette: BlendPalette.sunsetPastel
    )

    static func listening(level: Double) -> BlendCapsuleStyle {
        BlendCapsuleStyle(
            level: max(0.12, min(max(level, 0), 1)),
            isActive: true,
            palette: BlendPalette.sunsetPastel
        )
    }

    static let processing = BlendCapsuleStyle(
        level: 0.28,
        isActive: true,
        palette: BlendPalette.sunsetPastel
    )

    static let result = BlendCapsuleStyle(
        level: 0.16,
        isActive: false,
        palette: BlendPalette.sunsetPastel
    )

    static let error = BlendCapsuleStyle(
        level: 0.18,
        isActive: false,
        palette: BlendPalette.error
    )
}

private enum BlendPalette {
    static let surface = LinearGradient(
        colors: [
            Color(red: 0.86, green: 0.84, blue: 0.93),
            Color(red: 0.93, green: 0.77, blue: 0.73)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let base = LinearGradient(
        colors: [
            Color(red: 0.82, green: 0.83, blue: 0.96),
            Color(red: 0.90, green: 0.68, blue: 0.76),
            Color(red: 0.93, green: 0.62, blue: 0.50)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let sunsetPastel: [Color] = [
        Color(red: 0.74, green: 0.78, blue: 0.98),
        Color(red: 0.88, green: 0.67, blue: 0.84),
        Color(red: 0.92, green: 0.64, blue: 0.62),
        Color(red: 0.93, green: 0.61, blue: 0.39),
        Color(red: 0.95, green: 0.78, blue: 0.44)
    ]

    static let error: [Color] = [
        Color(red: 0.96, green: 0.66, blue: 0.72),
        Color(red: 0.95, green: 0.56, blue: 0.56),
        Color(red: 0.96, green: 0.66, blue: 0.46),
        Color(red: 0.82, green: 0.62, blue: 0.96),
        Color(red: 0.93, green: 0.78, blue: 0.50)
    ]
}

private struct VoiceLevelBarsView: View {
    let level: Double
    let layout: MacDictationPanelLayout

    private let multipliers: [CGFloat] = [0.18, 0.34, 0.56, 0.82, 1, 0.82, 0.56, 0.34, 0.18]

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(Array(multipliers.enumerated()), id: \.offset) { _, multiplier in
                Capsule()
                    .fill(Color.white)
                    .frame(width: 5, height: barHeight(multiplier: multiplier))
                    .opacity(0.68 + 0.32 * level)
            }
        }
        .frame(height: layout.voiceBarHeight)
        .animation(.interactiveSpring(response: 0.16, dampingFraction: 0.68), value: level)
    }

    private func barHeight(multiplier: CGFloat) -> CGFloat {
        let baseHeight: CGFloat = 3
        let responsiveLevel = CGFloat(pow(max(level, 0.02), 0.82))
        let variableHeight = responsiveLevel * (layout.voiceBarHeight - baseHeight) * multiplier
        return baseHeight + variableHeight
    }
}
#endif
