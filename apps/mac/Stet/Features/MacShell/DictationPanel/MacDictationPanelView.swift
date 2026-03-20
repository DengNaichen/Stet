#if os(macOS)
import SwiftUI

// MARK: - Constants

private enum Constants {
    enum Layout {
        static let mainWidthIdle: CGFloat = 250
        static let mainWidthStarting: CGFloat = 250
        static let mainWidthListening: CGFloat = 250
        static let mainWidthProcessing: CGFloat = 228
        static let mainWidthResult: CGFloat = 270
        static let mainWidthClipboard: CGFloat = 320
        static let mainWidthError: CGFloat = 300
        
        static let controlHeight: CGFloat = 52
        static let clipboardHeight: CGFloat = 118
        static let clipboardCornerRadius: CGFloat = 30

        static let offsetXListening: CGFloat = 12
        static let offsetXAlternate: CGFloat = 24
        
        static let offsetYDefault: CGFloat = -4
        static let offsetYClipboard: CGFloat = -2
        
        static let orbInset: CGFloat = 18
        static let orbTargetXDefault: CGFloat = 55
        static let orbTargetXClipboard: CGFloat = 46
        
        static let glassSpacing: CGFloat = 28
        static let orbScaleMin: CGFloat = 0.24
        static let orbScaleMax: CGFloat = 1.0
        static let orbAlphaThreshold: CGFloat = 0.01
        
        static let strokeOpacityClipboard: Double = 0.18
        static let strokeOpacityDefault: Double = 0.08
        static let strokeWidth: CGFloat = 0.9
        
        static let shadowRadiusClipboard: CGFloat = 18
        static let shadowRadiusDefault: CGFloat = 8
        static let shadowOpacityClipboard: Double = 0.22
        static let shadowOpacityDefault: Double = 0.12
        static let shadowYClipboard: CGFloat = 10
        static let shadowYDefault: CGFloat = 4
    }
    
    enum Animation {
        static let generalResponse: Double = 0.56
        static let generalDamping: Double = 0.82
        
        static let entranceResponse: Double = 0.50
        static let entranceDamping: Double = 0.68
        
        static let sideOrbResponse: Double = 0.56
        static let sideOrbDamping: Double = 0.78
        
        static let sideOrbExitDamping: Double = 0.80
        
        static let clipboardResponse: Double = 0.30
        static let clipboardDamping: Double = 0.90
        
        static let entranceDelay: UInt64 = 90_000_000
        static let orbTransitionDelay: UInt64 = 220_000_000
        static let clipboardDelay: UInt64 = 90_000_000
        static let symmetricCloseDelay: UInt64 = 90_000_000
        static let finalActionDelay: UInt64 = 240_000_000
    }
    
    enum VoiceReactivity {
        static let easedPower: Double = 0.45
        
        static let levelBaseIdle: Double = 0.10
        static let levelBaseStarting: Double = 0.15
        static let levelMultStarting: Double = 0.45
        static let levelMaxStarting: Double = 0.60
        static let levelBaseListening: Double = 0.22
        static let levelMultListening: Double = 0.78
        static let levelMaxListening: Double = 1.0
        static let levelBaseProcessing: Double = 0.08
        static let levelBaseResult: Double = 0.10
        
        static let shaderFrameIntervalActive: Double = 1.0 / 40.0
        static let shaderFrameIntervalIdle: Double = 1.0 / 30.0
    }
    
    enum Colors {
        static let errorGradientTop = Color(red: 0.78, green: 0.42, blue: 0.52)
        static let errorGradientBottom = Color(red: 0.93, green: 0.48, blue: 0.34)
        
        static let topLerpStart = (0.40, 0.85, 1.00)
        static let topLerpEnd = (0.20, 0.92, 1.00)
        static let midLerpStart = (0.85, 0.92, 0.98)
        static let midLerpEnd = (0.90, 0.95, 1.00)
        static let lowLerpStart = (0.80, 0.82, 0.85)
        static let lowLerpEnd = (0.45, 0.48, 0.55)
    }
}

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

    private var isVoiceReactiveState: Bool {
        switch state {
        case .starting, .listening:
            return true
        default:
            return false
        }
    }

    private var displayLevel: Double {
        let easedLevel = pow(normalizedRecordingLevel, Constants.VoiceReactivity.easedPower)

        switch state {
        case .idle:
            return Constants.VoiceReactivity.levelBaseIdle
        case .starting:
            return min(Constants.VoiceReactivity.levelMaxStarting, Constants.VoiceReactivity.levelBaseStarting + easedLevel * Constants.VoiceReactivity.levelMultStarting)
        case .listening:
            return min(Constants.VoiceReactivity.levelMaxListening, Constants.VoiceReactivity.levelBaseListening + easedLevel * Constants.VoiceReactivity.levelMultListening)
        case .processing:
            return Constants.VoiceReactivity.levelBaseProcessing
        case .result:
            return Constants.VoiceReactivity.levelBaseResult
        case .clipboardPending, .error:
            return 0
        }
    }

    private var mainWidth: CGFloat {
        switch state {
        case .idle:
            scaled(Constants.Layout.mainWidthIdle)
        case .starting:
            scaled(Constants.Layout.mainWidthStarting)
        case .listening:
            scaled(Constants.Layout.mainWidthListening)
        case .processing:
            scaled(Constants.Layout.mainWidthProcessing)
        case .result:
            scaled(Constants.Layout.mainWidthResult)
        case .clipboardPending:
            scaled(Constants.Layout.mainWidthClipboard)
        case .error:
            scaled(Constants.Layout.mainWidthError)
        }
    }

    private var controlHeight: CGFloat {
        scaled(Constants.Layout.controlHeight)
    }

    private var mainHeight: CGFloat {
        isClipboardPending ? scaled(Constants.Layout.clipboardHeight) : controlHeight
    }

    private var mainCornerRadius: CGFloat {
        isClipboardPending ? scaled(Constants.Layout.clipboardCornerRadius) : mainHeight / 2
    }

    private var mainOffsetX: CGFloat {
        switch state {
        case .idle, .starting, .listening:
            scaled(Constants.Layout.offsetXListening)
        case .clipboardPending:
            0
        case .processing, .result, .error:
            scaled(Constants.Layout.offsetXAlternate)
        }
    }

    private var mainOffsetY: CGFloat {
        isClipboardPending ? scaled(Constants.Layout.offsetYClipboard) : scaled(Constants.Layout.offsetYDefault)
    }

    private var leadingOrbProgress: CGFloat {
        visibleLeadingOrb == nil ? 0 : sideOrbProgress
    }

    private var trailingOrbProgress: CGFloat {
        visibleTrailingOrb == nil ? 0 : sideOrbProgress
    }

    private var leadingOrbX: CGFloat {
        let startX = mainOffsetX - (mainWidth / 2) + scaled(Constants.Layout.orbInset)
        let targetX = mainOffsetX - (mainWidth / 2) - scaled(isClipboardPending ? Constants.Layout.orbTargetXClipboard : Constants.Layout.orbTargetXDefault)
        return startX + (targetX - startX) * leadingOrbProgress
    }

    private var trailingOrbX: CGFloat {
        let startX = mainOffsetX + (mainWidth / 2) - scaled(Constants.Layout.orbInset)
        let targetX = mainOffsetX + (mainWidth / 2) + scaled(isClipboardPending ? Constants.Layout.orbTargetXClipboard : Constants.Layout.orbTargetXDefault)
        return startX + (targetX - startX) * trailingOrbProgress
    }

    private var orbSize: CGFloat {
        controlHeight
    }

    private var shaderFrameInterval: Double {
        isVoiceReactiveState ? Constants.VoiceReactivity.shaderFrameIntervalActive : Constants.VoiceReactivity.shaderFrameIntervalIdle
    }

    var body: some View {
        ZStack {
            GlassEffectContainer(spacing: scaled(Constants.Layout.glassSpacing)) {
                ZStack {
                    if let leadingOrb = visibleLeadingOrb {
                        capsuleOrbButton(leadingOrb)
                            .offset(x: leadingOrbX, y: mainOffsetY)
                            .scaleEffect(Constants.Layout.orbScaleMin + (Constants.Layout.orbScaleMax - Constants.Layout.orbScaleMin) * leadingOrbProgress)
                            .opacity(leadingOrbProgress)
                            .allowsHitTesting(leadingOrbProgress > Constants.Layout.orbAlphaThreshold)
                    }

                    if let trailingOrb = visibleTrailingOrb {
                        capsuleOrbButton(trailingOrb)
                            .offset(x: trailingOrbX, y: mainOffsetY)
                            .scaleEffect(Constants.Layout.orbScaleMin + (Constants.Layout.orbScaleMax - Constants.Layout.orbScaleMin) * trailingOrbProgress)
                            .opacity(trailingOrbProgress)
                            .allowsHitTesting(trailingOrbProgress > Constants.Layout.orbAlphaThreshold)
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
    }

    @ViewBuilder
    private func mainCapsule() -> some View {
        let size = CGSize(width: mainWidth, height: mainHeight)
        let shape = RoundedRectangle(cornerRadius: mainCornerRadius, style: .continuous)

        capsuleFill(size: size)
            .frame(width: size.width, height: size.height)
            .clipShape(shape)
            .glassEffect(.clear, in: shape)
            .overlay {
                shape.strokeBorder(.white.opacity(isClipboardPending ? Constants.Layout.strokeOpacityClipboard : Constants.Layout.strokeOpacityDefault), lineWidth: scaled(Constants.Layout.strokeWidth))
            }
            .shadow(
                color: .black.opacity(isClipboardPending ? Constants.Layout.shadowOpacityClipboard : Constants.Layout.shadowOpacityDefault),
                radius: isClipboardPending ? scaled(Constants.Layout.shadowRadiusClipboard) : scaled(Constants.Layout.shadowRadiusDefault),
                y: isClipboardPending ? scaled(Constants.Layout.shadowYClipboard) : scaled(Constants.Layout.shadowYDefault)
            )
            .animation(.spring(response: Constants.Animation.generalResponse, dampingFraction: Constants.Animation.generalDamping), value: state)
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
                            Constants.Colors.errorGradientTop.opacity(0.42),
                            Constants.Colors.errorGradientBottom.opacity(0.24)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        } else {
            TimelineView(.animation(minimumInterval: shaderFrameInterval, paused: false)) { timeline in
                let level = displayLevel
                let talk = min(max(level, 0.0), 1.0)
                let breath = talk * talk * (3.0 - 2.0 * talk)

                let top = Color(
                    red:   lerp(Constants.Colors.topLerpStart.0, Constants.Colors.topLerpEnd.0, breath),
                    green: lerp(Constants.Colors.topLerpStart.1, Constants.Colors.topLerpEnd.1, breath),
                    blue:  lerp(Constants.Colors.topLerpStart.2, Constants.Colors.topLerpEnd.2, breath)
                )
                let mid = Color(
                    red:   lerp(Constants.Colors.midLerpStart.0, Constants.Colors.midLerpEnd.0, breath),
                    green: lerp(Constants.Colors.midLerpStart.1, Constants.Colors.midLerpEnd.1, breath),
                    blue:  lerp(Constants.Colors.midLerpStart.2, Constants.Colors.midLerpEnd.2, breath)
                )
                let low = Color(
                    red:   lerp(Constants.Colors.lowLerpStart.0, Constants.Colors.lowLerpEnd.0, breath),
                    green: lerp(Constants.Colors.lowLerpStart.1, Constants.Colors.lowLerpEnd.1, breath),
                    blue:  lerp(Constants.Colors.lowLerpStart.2, Constants.Colors.lowLerpEnd.2, breath)
                )

                Rectangle()
                    .fill(.white)
                    .colorEffect(
                        ShaderLibrary.cloudOrbGlassWide(
                            .float2(size),
                            .float(timeline.date.timeIntervalSince(startDate)),
                            .float(level),
                            .color(top),
                            .color(mid),
                            .color(low)
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

        let pendingLeadingOrb = leadingOrb
        let pendingTrailingOrb = trailingOrb

        visibleLeadingOrb = nil
        visibleTrailingOrb = nil

        withAnimation(.spring(response: Constants.Animation.entranceResponse, dampingFraction: Constants.Animation.entranceDamping)) {
            appeared = true
        }

        entranceTask?.cancel()
        entranceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Constants.Animation.entranceDelay)
            guard !Task.isCancelled else { return }

            visibleLeadingOrb = pendingLeadingOrb
            visibleTrailingOrb = pendingTrailingOrb

            withAnimation(.spring(response: Constants.Animation.sideOrbResponse, dampingFraction: Constants.Animation.sideOrbDamping)) {
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
                withAnimation(.spring(response: Constants.Animation.sideOrbResponse, dampingFraction: Constants.Animation.sideOrbDamping)) {
                    sideOrbProgress = 1
                }
            } else {
                sideOrbProgress = 1
            }
            return
        }

        guard visibleLeadingOrb != nil || visibleTrailingOrb != nil else { return }

        if shouldAnimateOrbTransition {
            withAnimation(.spring(response: Constants.Animation.sideOrbResponse, dampingFraction: Constants.Animation.sideOrbExitDamping)) {
                sideOrbProgress = 0
            }
        } else {
            sideOrbProgress = 0
        }

        if shouldAnimateOrbTransition {
            orbTransitionTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: Constants.Animation.orbTransitionDelay)
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
            try? await Task.sleep(nanoseconds: Constants.Animation.clipboardDelay)
            guard !Task.isCancelled else { return }

            withAnimation(.spring(response: Constants.Animation.clipboardResponse, dampingFraction: Constants.Animation.clipboardDamping)) {
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

        withAnimation(.spring(response: Constants.Animation.sideOrbResponse, dampingFraction: Constants.Animation.sideOrbDamping)) {
            sideOrbProgress = 0
        }

        exitTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Constants.Animation.symmetricCloseDelay)
            guard !Task.isCancelled else { return }

            withAnimation(.spring(response: Constants.Animation.entranceResponse, dampingFraction: Constants.Animation.entranceDamping)) {
                appeared = false
            }

            try? await Task.sleep(nanoseconds: Constants.Animation.finalActionDelay)
            guard !Task.isCancelled else { return }

            action()
        }
    }

    private func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
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
