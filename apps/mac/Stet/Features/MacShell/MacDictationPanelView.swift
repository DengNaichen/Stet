#if os(macOS)
import SwiftUI

struct MacDictationPanelView: View {
    @StateObject private var viewModel: MacDictationPanelViewModel

    let layout: MacDictationPanelLayout

    init(layout: MacDictationPanelLayout, appModel: any MacDictationPanelCoordinating) {
        self.layout = layout
        _viewModel = StateObject(wrappedValue: MacDictationPanelViewModel(appModel: appModel))
    }

    var body: some View {
        let panelSize = layout.panelSize(for: viewModel.state)

        MacDictationCapsuleSurface(
            layout: layout,
            panelSize: panelSize,
            state: viewModel.state,
            statusText: viewModel.statusText,
            recordingLevel: viewModel.recordingLevel,
            leadingOrb: leadingOrb,
            trailingOrb: trailingOrb
        )
        .frame(width: panelSize.width, height: panelSize.height)
    }

    private var leadingOrb: CapsuleOrbConfiguration? {
        switch viewModel.state {
        case .idle:
            CapsuleOrbConfiguration(
                systemName: "xmark",
                tint: .cancel,
                action: viewModel.hidePanel
            )
        case .listening:
            CapsuleOrbConfiguration(
                systemName: "xmark",
                tint: .cancel,
                action: viewModel.cancelActiveCapture
            )
        case .processing:
            nil
        case .result:
            nil
        case .clipboardPending:
            CapsuleOrbConfiguration(
                systemName: "xmark",
                tint: .cancel,
                action: viewModel.dismissPendingCopy
            )
        case .error:
            CapsuleOrbConfiguration(
                systemName: "xmark",
                tint: .cancel,
                action: viewModel.hidePanel
            )
        }
    }

    private var trailingOrb: CapsuleOrbConfiguration? {
        switch viewModel.state {
        case .idle:
            CapsuleOrbConfiguration(
                systemName: "mic.fill",
                tint: .primaryAction,
                action: viewModel.performPrimaryAction
            )
        case .listening:
            CapsuleOrbConfiguration(
                systemName: "checkmark",
                tint: .primaryAction,
                action: viewModel.performPrimaryAction
            )
        case .processing:
            nil
        case .result:
            nil
        case .clipboardPending:
            CapsuleOrbConfiguration(
                systemName: "doc.on.doc",
                tint: .copyAction,
                action: viewModel.performPrimaryAction
            )
        case .error:
            CapsuleOrbConfiguration(
                systemName: "arrow.clockwise",
                tint: .retryAction,
                action: viewModel.performPrimaryAction
            )
        }
    }
}

private struct MacDictationCapsuleSurface: View {
    let layout: MacDictationPanelLayout
    let panelSize: CGSize
    let state: DictationState
    let statusText: String
    let recordingLevel: Double
    let leadingOrb: CapsuleOrbConfiguration?
    let trailingOrb: CapsuleOrbConfiguration?

    @State private var appeared = false
    @State private var startDate = Date()

    private var scale: CGFloat {
        layout.scale
    }

    private var canvasSize: CGSize {
        panelSize
    }

    private var isClipboardPending: Bool {
        if case .clipboardPending = state {
            return true
        }

        return false
    }

    private var isProcessing: Bool {
        if case .processing = state {
            return true
        }

        return false
    }

    private var isError: Bool {
        if case .error = state {
            return true
        }

        return false
    }

    private var normalizedRecordingLevel: Double {
        min(max(recordingLevel, 0), 1)
    }

    private var displayLevel: Double {
        switch state {
        case .idle:
            return 0.14
        case .listening:
            return min(max(0.12 + normalizedRecordingLevel * 0.88, 0), 1)
        case .processing:
            return 0.08
        case .result:
            return 0.12
        case .clipboardPending, .error:
            return 0
        }
    }

    private var mainWidth: CGFloat {
        switch state {
        case .idle:
            scaled(250)
        case .listening:
            scaled(250)
        case .processing:
            scaled(228)
        case .result:
            scaled(270)
        case .clipboardPending:
            scaled(320)
        case .error:
            scaled(300)
        }
    }

    private var mainHeight: CGFloat {
        isClipboardPending ? scaled(118) : scaled(52)
    }

    private var mainCornerRadius: CGFloat {
        isClipboardPending ? scaled(30) : mainHeight / 2
    }

    private var mainOffsetX: CGFloat {
        switch state {
        case .idle, .listening:
            scaled(12)
        case .clipboardPending:
            0
        case .processing, .result, .error:
            scaled(24)
        }
    }

    private var mainOffsetY: CGFloat {
        isClipboardPending ? scaled(-2) : scaled(-4)
    }

    private var leadingOrbProgress: CGFloat {
        leadingOrb == nil ? 0 : 1
    }

    private var trailingOrbProgress: CGFloat {
        trailingOrb == nil ? 0 : 1
    }

    private var leadingOrbX: CGFloat {
        let startX = mainOffsetX - (mainWidth / 2) + scaled(18)
        let targetX = mainOffsetX - (mainWidth / 2) - scaled(isClipboardPending ? 46 : 55)
        return startX + (targetX - startX) * leadingOrbProgress
    }

    private var trailingOrbX: CGFloat {
        let startX = mainOffsetX + (mainWidth / 2) - scaled(18)
        let targetX = mainOffsetX + (mainWidth / 2) + scaled(isClipboardPending ? 46 : 55)
        return startX + (targetX - startX) * trailingOrbProgress
    }

    private var orbSize: CGFloat {
        scaled(52)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { timeline in
            let elapsed = timeline.date.timeIntervalSince(startDate)

            ZStack {
                GlassEffectContainer(spacing: scaled(28)) {
                    ZStack {
                        if let leadingOrb {
                            capsuleOrbButton(leadingOrb, elapsed: elapsed)
                                .offset(x: leadingOrbX, y: mainOffsetY)
                                .scaleEffect(0.24 + 0.76 * leadingOrbProgress)
                                .opacity(leadingOrbProgress)
                                .allowsHitTesting(leadingOrbProgress > 0.01)
                        }

                        mainCapsule(elapsed: elapsed)
                            .offset(x: mainOffsetX, y: mainOffsetY)

                        if let trailingOrb {
                            capsuleOrbButton(trailingOrb, elapsed: elapsed)
                                .offset(x: trailingOrbX, y: mainOffsetY)
                                .scaleEffect(0.24 + 0.76 * trailingOrbProgress)
                                .opacity(trailingOrbProgress)
                                .allowsHitTesting(trailingOrbProgress > 0.01)
                        }
                    }
                    .frame(width: canvasSize.width, height: canvasSize.height)
                }

                mainContent(elapsed: elapsed)
                    .frame(width: mainWidth, height: mainHeight)
                    .offset(x: mainOffsetX, y: mainOffsetY)
            }
            .frame(width: canvasSize.width, height: canvasSize.height)
        }
        .scaleEffect(appeared ? 1.0 : 0.94)
        .opacity(appeared ? 1.0 : 0.0)
        .onAppear {
            if !appeared {
                withAnimation(.spring(response: 0.46, dampingFraction: 0.78)) {
                    appeared = true
                }
            }
        }
        .animation(.spring(response: 0.56, dampingFraction: 0.82), value: state)
    }

    @ViewBuilder
    private func mainCapsule(elapsed: Double) -> some View {
        GeometryReader { proxy in
            if isClipboardPending {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.18),
                                .white.opacity(0.10)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            } else if isError {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.78, green: 0.42, blue: 0.52).opacity(0.42),
                                Color(red: 0.93, green: 0.48, blue: 0.34).opacity(0.24)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            } else {
                Rectangle()
                    .fill(.white)
                    .colorEffect(
                        ShaderLibrary.cloudOrbGlassWide(
                            .float2(proxy.size),
                            .float(elapsed),
                            .float(displayLevel)
                        )
                    )
            }
        }
        .frame(width: mainWidth, height: mainHeight)
        .clipShape(RoundedRectangle(cornerRadius: mainCornerRadius, style: .continuous))
        .glassEffect(.clear, in: RoundedRectangle(cornerRadius: mainCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: mainCornerRadius, style: .continuous)
                .strokeBorder(.white.opacity(isClipboardPending ? 0.18 : 0.08), lineWidth: scaled(0.9))
        }
        .shadow(
            color: .black.opacity(isClipboardPending ? 0.22 : 0.12),
            radius: isClipboardPending ? scaled(18) : scaled(8),
            y: isClipboardPending ? scaled(10) : scaled(4)
        )
    }

    @ViewBuilder
    private func mainContent(elapsed: Double) -> some View {
        switch state {
        case .processing:
            processingContent(elapsed: elapsed)
        case .clipboardPending(let text):
            clipboardContent(text: text)
        case .error(let message):
            messageText(
                message,
                fontSize: 13,
                lineLimit: 3,
                minimumScaleFactor: 0.9
            )
            .padding(.horizontal, scaled(24))
        case .result:
            HStack(spacing: scaled(8)) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: scaled(16), weight: .semibold))
                    .foregroundStyle(.white.opacity(0.96))

                messageText(statusText, fontSize: 13, lineLimit: 1, minimumScaleFactor: 0.92)
            }
            .padding(.horizontal, scaled(20))
        case .idle, .listening:
            messageText(statusText, fontSize: 13, lineLimit: 1, minimumScaleFactor: 0.86)
                .padding(.horizontal, scaled(22))
        }
    }

    @ViewBuilder
    private func processingContent(elapsed: Double) -> some View {
        VStack(spacing: scaled(8)) {
            processingDots(elapsed: elapsed)

            if statusText != DictationState.processing.statusText {
                messageText(statusText, fontSize: 11, lineLimit: 1, minimumScaleFactor: 0.85)
                    .opacity(0.82)
            }
        }
        .padding(.horizontal, scaled(16))
    }

    @ViewBuilder
    private func clipboardContent(text: String) -> some View {
        Text(text)
            .font(.system(size: scaled(15), weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.96))
            .multilineTextAlignment(.center)
            .lineSpacing(scaled(4))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, scaled(24))
            .padding(.vertical, scaled(18))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    @ViewBuilder
    private func messageText(
        _ text: String,
        fontSize: CGFloat,
        lineLimit: Int,
        minimumScaleFactor: CGFloat
    ) -> some View {
        Text(text)
            .font(.system(size: scaled(fontSize), weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.96))
            .lineLimit(lineLimit)
            .minimumScaleFactor(minimumScaleFactor)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .multilineTextAlignment(.center)
            .shadow(color: .black.opacity(0.16), radius: scaled(10), y: scaled(4))
    }

    @ViewBuilder
    private func processingDots(elapsed: Double) -> some View {
        HStack(spacing: scaled(5)) {
            let cadence = elapsed * 3.2
            let head = Int(floor(cadence)).quotientAndRemainder(dividingBy: 3).remainder
            let progress = cadence - floor(cadence)

            ForEach(0..<3, id: \.self) { index in
                let isHead = index == head
                let isTrailing = index == (head + 2) % 3
                let headGlow = isHead ? (0.72 + 0.28 * progress) : 0.0
                let trailingGlow = isTrailing ? (0.42 * (1.0 - progress)) : 0.0
                let intensity = max(headGlow, trailingGlow)
                let opacity = 0.36 + intensity * 0.64
                let scale = 0.82 + intensity * 0.34
                let yOffset = -1.2 * intensity

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                .white.opacity(min(1.0, opacity + 0.18)),
                                Color.primaryAction.opacity(opacity)
                            ],
                            center: .center,
                            startRadius: scaled(0.5),
                            endRadius: scaled(4)
                        )
                    )
                    .frame(width: scaled(6.5), height: scaled(6.5))
                    .scaleEffect(scale)
                    .offset(y: scaled(yOffset))
                    .shadow(color: Color.primaryAction.opacity(0.26 + intensity * 0.34), radius: scaled(6))
            }
        }
        .frame(height: scaled(18))
    }

    @ViewBuilder
    private func capsuleOrbButton(
        _ configuration: CapsuleOrbConfiguration,
        elapsed: Double
    ) -> some View {
        Button(action: configuration.action) {
            Color.clear
                .frame(width: orbSize, height: orbSize)
                .glassEffect(.clear, in: Circle())
                .overlay {
                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        configuration.tint.opacity(0.38 + displayLevel * 0.10),
                                        configuration.tint.opacity(0.18 + displayLevel * 0.06),
                                        configuration.tint.opacity(0.04),
                                        .clear
                                    ],
                                    center: .center,
                                    startRadius: scaled(2),
                                    endRadius: orbSize * 0.48
                                )
                            )
                            .frame(width: orbSize - scaled(6), height: orbSize - scaled(6))
                            .scaleEffect(1.0 + displayLevel * 0.07)

                        Circle()
                            .fill(.white.opacity(0.06))
                            .frame(width: orbSize - scaled(20), height: orbSize - scaled(20))

                        Circle()
                            .strokeBorder(configuration.tint.opacity(0.36), lineWidth: scaled(1.2))
                            .frame(width: orbSize - scaled(16), height: orbSize - scaled(16))

                        Circle()
                            .strokeBorder(.white.opacity(0.14), lineWidth: scaled(0.8))
                            .frame(width: orbSize - scaled(8), height: orbSize - scaled(8))

                        Image(systemName: configuration.systemName)
                            .font(.system(size: scaled(16), weight: .bold))
                            .foregroundStyle(.white.opacity(0.96))
                            .shadow(color: configuration.tint.opacity(0.45), radius: scaled(6))
                    }
                }
        }
        .buttonStyle(.plain)
        .shadow(color: configuration.tint.opacity(0.16), radius: scaled(10))
        .accessibilityLabel(configuration.systemName)
    }

    private func scaled(_ value: CGFloat) -> CGFloat {
        value * scale
    }
}

private struct CapsuleOrbConfiguration {
    let systemName: String
    let tint: Color
    let action: () -> Void
}

private extension Color {
    static let cancel = Color(
        red: 218.0 / 255.0,
        green: 152.0 / 255.0,
        blue: 218.0 / 255.0
    )

    static let primaryAction = Color(
        red: 179.0 / 255.0,
        green: 190.0 / 255.0,
        blue: 250.0 / 255.0
    )

    static let copyAction = Color(
        red: 192.0 / 255.0,
        green: 218.0 / 255.0,
        blue: 1.0
    )

    static let retryAction = Color(
        red: 1.0,
        green: 180.0 / 255.0,
        blue: 124.0 / 255.0
    )
}
#endif
