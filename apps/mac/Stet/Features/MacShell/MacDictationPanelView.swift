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
        let panelSize = layout.panelSize

        MacDictationCapsuleSurface(
            layout: layout,
            panelSize: panelSize,
            state: viewModel.state,
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
                accessibilityLabel: "Cancel",
                triggersSymmetricClose: true,
                action: viewModel.hidePanel
            )
        case .listening:
            CapsuleOrbConfiguration(
                systemName: "xmark",
                accessibilityLabel: "Cancel",
                triggersSymmetricClose: true,
                action: viewModel.cancelActiveCapture
            )
        case .starting:
            CapsuleOrbConfiguration(
                systemName: "xmark",
                accessibilityLabel: "Cancel",
                triggersSymmetricClose: true,
                action: viewModel.cancelActiveCapture
            )
        case .processing:
            nil
        case .result:
            nil
        case .clipboardPending:
            nil
        case .error:
            CapsuleOrbConfiguration(
                systemName: "xmark",
                accessibilityLabel: "Cancel",
                triggersSymmetricClose: true,
                action: viewModel.hidePanel
            )
        }
    }

    private var trailingOrb: CapsuleOrbConfiguration? {
        switch viewModel.state {
        case .idle:
            CapsuleOrbConfiguration(
                systemName: "mic.fill",
                accessibilityLabel: "Start Dictation",
                action: viewModel.performPrimaryAction
            )
        case .starting:
            nil
        case .listening:
            CapsuleOrbConfiguration(
                systemName: "checkmark",
                accessibilityLabel: "Finish Dictation",
                action: viewModel.performPrimaryAction
            )
        case .processing:
            nil
        case .result:
            nil
        case .clipboardPending:
            CapsuleOrbConfiguration(
                systemName: "doc.on.doc",
                accessibilityLabel: "Copy",
                action: viewModel.performPrimaryAction
            )
        case .error:
            CapsuleOrbConfiguration(
                systemName: "arrow.clockwise",
                accessibilityLabel: "Retry",
                action: viewModel.performPrimaryAction
            )
        }
    }
}

private struct MacDictationCapsuleSurface: View {
    let layout: MacDictationPanelLayout
    let panelSize: CGSize
    let state: DictationState
    let recordingLevel: Double
    let leadingOrb: CapsuleOrbConfiguration?
    let trailingOrb: CapsuleOrbConfiguration?

    @State private var appeared = false
    @State private var sideOrbProgress: CGFloat = 0
    @State private var hasAnimatedEntrance = false
    @State private var entranceTask: Task<Void, Never>?
    @State private var orbTransitionTask: Task<Void, Never>?
    @State private var clipboardRevealTask: Task<Void, Never>?
    @State private var exitTask: Task<Void, Never>?
    @State private var visibleLeadingOrb: CapsuleOrbConfiguration?
    @State private var visibleTrailingOrb: CapsuleOrbConfiguration?
    @State private var clipboardContentVisible = false
    @State private var isExitAnimating = false
    @State private var startDate = Date()
    @State private var previousState: DictationState?

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
        case .starting:
            return 0.08
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
        case .starting:
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

    private var controlHeight: CGFloat {
        scaled(52)
    }

    private var mainHeight: CGFloat {
        isClipboardPending ? scaled(118) : controlHeight
    }

    private var mainCornerRadius: CGFloat {
        isClipboardPending ? scaled(30) : mainHeight / 2
    }

    private var mainOffsetX: CGFloat {
        switch state {
        case .idle, .starting, .listening:
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
        visibleLeadingOrb == nil ? 0 : sideOrbProgress
    }

    private var trailingOrbProgress: CGFloat {
        visibleTrailingOrb == nil ? 0 : sideOrbProgress
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
        controlHeight
    }

    private var shaderFrameInterval: Double {
        1.0 / 30.0
    }

    var body: some View {
        ZStack {
            GlassEffectContainer(spacing: scaled(28)) {
                ZStack {
                    if let leadingOrb = visibleLeadingOrb {
                        capsuleOrbButton(leadingOrb)
                            .offset(x: leadingOrbX, y: mainOffsetY)
                            .scaleEffect(0.24 + 0.76 * leadingOrbProgress)
                            .opacity(leadingOrbProgress)
                            .allowsHitTesting(leadingOrbProgress > 0.01)
                    }

                    if let trailingOrb = visibleTrailingOrb {
                        capsuleOrbButton(trailingOrb)
                            .offset(x: trailingOrbX, y: mainOffsetY)
                            .scaleEffect(0.24 + 0.76 * trailingOrbProgress)
                            .opacity(trailingOrbProgress)
                            .allowsHitTesting(trailingOrbProgress > 0.01)
                    }

                    mainCapsule()
                        .offset(x: mainOffsetX, y: mainOffsetY)
                }
                .frame(width: canvasSize.width, height: canvasSize.height)
            }

            mainContent()
                .frame(width: mainWidth, height: mainHeight)
                .offset(x: mainOffsetX, y: mainOffsetY)
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .scaleEffect(appeared ? 1.0 : 0.3)
        .opacity(appeared ? 1.0 : 0.0)
        .onAppear {
            runEntranceAnimationIfNeeded()
            syncClipboardPresentation(animated: false)
            previousState = state
        }
        .onChange(of: state) {
            guard !isExitAnimating else { return }
            syncSideOrbVisibility(from: previousState, to: state)
            syncClipboardPresentation(animated: true)
            previousState = state
        }
        .onDisappear(perform: resetEntranceAnimation)
        .animation(.spring(response: 0.56, dampingFraction: 0.82), value: state)
    }

    @ViewBuilder
    private func mainCapsule() -> some View {
        GeometryReader { proxy in
            capsuleFill(size: proxy.size)
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
    private func capsuleFill(size: CGSize) -> some View {
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
            TimelineView(.animation(minimumInterval: shaderFrameInterval, paused: false)) { timeline in
                Rectangle()
                    .fill(.white)
                    .colorEffect(
                        ShaderLibrary.cloudOrbGlassWide(
                            .float2(size),
                            .float(timeline.date.timeIntervalSince(startDate)),
                            .float(displayLevel)
                        )
                    )
            }
        }
    }

    @ViewBuilder
    private func mainContent() -> some View {
        switch state {
        case .processing:
            processingContent()
        case .clipboardPending(let text):
            clipboardContent(text: text)
        case .error(let failure):
            messageText(
                failure.message,
                fontSize: 13,
                lineLimit: 3,
                minimumScaleFactor: 0.9
            )
            .padding(.horizontal, scaled(24))
        case .result, .idle, .starting, .listening:
            EmptyView()
        }
    }

    @ViewBuilder
    private func processingContent() -> some View {
        processingDots()
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
            .opacity(clipboardContentVisible ? 1 : 0)
            .offset(y: clipboardContentVisible ? 0 : scaled(8))
            .scaleEffect(clipboardContentVisible ? 1 : 0.985)
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
    private func processingDots() -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { timeline in
            let elapsed = timeline.date.timeIntervalSince(startDate)

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
    }

    @ViewBuilder
    private func capsuleOrbButton(_ configuration: CapsuleOrbConfiguration) -> some View {
        Button(action: { handleOrbAction(configuration) }) {
            orbSymbol(configuration.systemName)
                .frame(width: orbSize, height: orbSize)
                .glassEffect(.regular, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(configuration.accessibilityLabel)
    }

    @ViewBuilder
    private func orbSymbol(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .symbolRenderingMode(.monochrome)
            .font(.system(size: scaled(16), weight: .semibold))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func scaled(_ value: CGFloat) -> CGFloat {
        value * scale
    }

    private func handleOrbAction(_ configuration: CapsuleOrbConfiguration) {
        if configuration.triggersSymmetricClose {
            runSymmetricCloseAnimation(perform: configuration.action)
            return
        }

        configuration.action()
    }

    private func runEntranceAnimationIfNeeded() {
        guard !hasAnimatedEntrance else { return }

        hasAnimatedEntrance = true
        isExitAnimating = false
        startDate = Date()
        appeared = false
        sideOrbProgress = 0
        visibleLeadingOrb = leadingOrb
        visibleTrailingOrb = trailingOrb

        withAnimation(.spring(response: 0.50, dampingFraction: 0.68)) {
            appeared = true
        }

        entranceTask?.cancel()
        entranceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 90_000_000)
            guard !Task.isCancelled else { return }

            withAnimation(.spring(response: 0.56, dampingFraction: 0.78)) {
                sideOrbProgress = 1
            }
        }
    }

    private func syncSideOrbVisibility(from previousState: DictationState?, to currentState: DictationState) {
        entranceTask?.cancel()
        orbTransitionTask?.cancel()

        let shouldShowSideOrbs = leadingOrb != nil || trailingOrb != nil
        let shouldAnimateOrbTransition = shouldAnimateSideOrbTransition(from: previousState, to: currentState)

        if shouldShowSideOrbs {
            visibleLeadingOrb = leadingOrb
            visibleTrailingOrb = trailingOrb

            if shouldAnimateOrbTransition {
                withAnimation(.spring(response: 0.56, dampingFraction: 0.78)) {
                    sideOrbProgress = 1
                }
            } else {
                sideOrbProgress = 1
            }
            return
        }

        guard visibleLeadingOrb != nil || visibleTrailingOrb != nil else { return }

        if shouldAnimateOrbTransition {
            withAnimation(.spring(response: 0.56, dampingFraction: 0.80)) {
                sideOrbProgress = 0
            }
        } else {
            sideOrbProgress = 0
        }

        if shouldAnimateOrbTransition {
            orbTransitionTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 220_000_000)
                guard !Task.isCancelled else { return }

                visibleLeadingOrb = nil
                visibleTrailingOrb = nil
            }
        } else {
            visibleLeadingOrb = nil
            visibleTrailingOrb = nil
        }
    }

    private func shouldAnimateSideOrbTransition(from previousState: DictationState?, to currentState: DictationState) -> Bool {
        guard let previousState else { return true }
        return !(previousState == .starting && currentState == .listening)
    }

    private func syncClipboardPresentation(animated: Bool) {
        clipboardRevealTask?.cancel()

        guard isClipboardPending else {
            clipboardContentVisible = false
            return
        }

        guard animated else {
            clipboardContentVisible = true
            return
        }

        clipboardContentVisible = false
        clipboardRevealTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 90_000_000)
            guard !Task.isCancelled else { return }

            withAnimation(.spring(response: 0.30, dampingFraction: 0.90)) {
                clipboardContentVisible = true
            }
        }
    }

    private func resetEntranceAnimation() {
        entranceTask?.cancel()
        orbTransitionTask?.cancel()
        clipboardRevealTask?.cancel()
        exitTask?.cancel()
        entranceTask = nil
        orbTransitionTask = nil
        clipboardRevealTask = nil
        exitTask = nil
        hasAnimatedEntrance = false
        appeared = false
        sideOrbProgress = 0
        clipboardContentVisible = false
        isExitAnimating = false
        visibleLeadingOrb = nil
        visibleTrailingOrb = nil
        previousState = nil
    }

    private func runSymmetricCloseAnimation(perform action: @escaping () -> Void) {
        guard !isExitAnimating else { return }

        isExitAnimating = true
        entranceTask?.cancel()
        orbTransitionTask?.cancel()
        clipboardRevealTask?.cancel()
        exitTask?.cancel()

        withAnimation(.spring(response: 0.56, dampingFraction: 0.78)) {
            sideOrbProgress = 0
        }

        exitTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 90_000_000)
            guard !Task.isCancelled else { return }

            withAnimation(.spring(response: 0.50, dampingFraction: 0.68)) {
                appeared = false
            }

            try? await Task.sleep(nanoseconds: 240_000_000)
            guard !Task.isCancelled else { return }

            action()
        }
    }
}

private struct CapsuleOrbConfiguration {
    let systemName: String
    let accessibilityLabel: String
    var triggersSymmetricClose: Bool = false
    let action: () -> Void
}

private extension Color {
    static let primaryAction = Color(
        red: 179.0 / 255.0,
        green: 190.0 / 255.0,
        blue: 250.0 / 255.0
    )
}
#endif
