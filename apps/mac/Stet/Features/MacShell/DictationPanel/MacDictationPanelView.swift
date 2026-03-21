#if os(macOS)
import SwiftUI

// MARK: - Constants

private enum Constants {
    enum Layout {
        static let mainWidthIdle: CGFloat = 200
        static let mainWidthStarting: CGFloat = 200
        static let mainWidthListening: CGFloat = 200
        static let mainWidthProcessing: CGFloat = 200
        static let mainWidthResult: CGFloat = 200
        static let mainWidthClipboard: CGFloat = 200
        static let mainWidthError: CGFloat = 200
        
        static let controlHeight: CGFloat = 40
        static let clipboardHeight: CGFloat = 118
        static let clipboardCornerRadius: CGFloat = 30

        static let offsetXListening: CGFloat = 12
        static let offsetXAlternate: CGFloat = 24
        
        static let offsetYDefault: CGFloat = -4
        static let offsetYClipboard: CGFloat = -2
        
        static let shadowRadiusClipboard: CGFloat = 18
        static let shadowRadiusDefault: CGFloat = 8
        static let shadowOpacityClipboard: Double = 0.22
        static let shadowOpacityDefault: Double = 0.12
        static let shadowYClipboard: CGFloat = 10
        static let shadowYDefault: CGFloat = 4
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
        // Base Neutral (Idle)
        static let topIdle = (0.95, 0.96, 0.98)
        static let midIdle = (0.86, 0.88, 0.90)
        static let lowIdle = (0.72, 0.74, 0.76)
        
        // Active Speaking (Blue Injection)
        static let topSpeaking = (0.35, 0.85, 1.00)
        static let midSpeaking = (0.20, 0.65, 1.00)
        static let lowSpeaking = (0.10, 0.45, 0.85)
        
        // Active Processing (Orange Injection)
        static let topProcessing = (1.00, 0.80, 0.45)
        static let midProcessing = (1.00, 0.55, 0.12)
        static let lowProcessing = (0.85, 0.32, 0.08)
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

        Group {
            if case .clipboardPending(let text) = viewModel.state {
                // Scenario B: Specialized Clipboard Display
                MacDictationClipboardSurface(
                    text: text,
                    layout: layout,
                    onFinish: viewModel.performPrimaryAction
                )
            } else {
                // Scenario A: Standard Dictation Capsule
                MacDictationCapsuleSurface(
                    viewModel: viewModel,
                    layout: layout,
                    panelSize: panelSize
                )
            }
        }
        .frame(width: panelSize.width, height: panelSize.height)
    }
}

// MARK: - Components

private struct MacDictationCapsuleSurface: View {
    @ObservedObject var viewModel: MacDictationPanelViewModel
    let layout: MacDictationPanelLayout
    let panelSize: CGSize

    private var state: DictationState {
        viewModel.state
    }

    private var recordingLevel: Double {
        viewModel.recordingLevel
    }
    @Namespace private var glassNamespace

    @State private var isPanelShown = false
    @State private var ShowIOrbs = true
    @State private var startDate = Date()

    private var scale: CGFloat {
        layout.scale
    }

    private var canvasSize: CGSize {
        panelSize
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
        case .result(_):
            return Constants.VoiceReactivity.levelBaseResult
        default:
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
        case .result(_):
            scaled(Constants.Layout.mainWidthResult)
        case .error(_):
            scaled(Constants.Layout.mainWidthError)
        case .clipboardPending(_):
            scaled(200)
        default:
            scaled(200)
        }
    }

    private var controlHeight: CGFloat {
        scaled(Constants.Layout.controlHeight)
    }

    private var shaderFrameInterval: Double {
        Constants.VoiceReactivity.shaderFrameIntervalActive
    }

    private var orbFontSize: CGFloat {
        controlHeight * 0.6
    }

    var body: some View {
        ZStack {
            // Background Layer: Orbs & Capsule
            ZStack {
                GlassEffectContainer(spacing: 40) {
                    HStack(spacing: 40) {
                        // Leading Orb
                        Button(action: handleCancelAction) {
                            Image(systemName: "xmark")
                                .font(.system(size: orbFontSize, weight: .bold))
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .frame(width: controlHeight, height: controlHeight)
                        .glassEffect(.regular)
                        .glassEffectID("cancel", in: glassNamespace)
                        .opacity(isPanelShown && ShowIOrbs ? 1 : 0)
                        .offset(x: isPanelShown && ShowIOrbs ? 0 : 200)
                        .scaleEffect(isPanelShown && ShowIOrbs ? 1 : 0.8)
                        .allowsHitTesting(isPanelShown && ShowIOrbs)

                        // Layer 2: Middle Material (Main Capsule)
                        Capsule()
                            .frame(width: mainWidth, height: controlHeight)
                            .glassEffect(.regular.tint(.white))
                            .glassEffectID("main", in: glassNamespace)

                        // Trailing Orb
                        Button(action: handleFinishAction) {
                            Image(systemName: "checkmark")
                                .font(.system(size: orbFontSize, weight: .bold))
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .frame(width: controlHeight, height: controlHeight)
                        .glassEffect(.regular)
                        .glassEffectID("done", in: glassNamespace)
                        .opacity(isPanelShown && ShowIOrbs ? 1 : 0)
                        .offset(x: isPanelShown && ShowIOrbs ? 0 : -200)
                        .scaleEffect(isPanelShown && ShowIOrbs ? 1 : 0.8)
                        .allowsHitTesting(isPanelShown && ShowIOrbs)
                    }
                }

                // Shader Layer
                MacDictationShaderLayer(
                    state: state,
                    mainWidth: mainWidth,
                    controlHeight: controlHeight,
                    startDate: startDate,
                    shaderFrameInterval: shaderFrameInterval,
                    displayLevel: displayLevel
                )
            }
            .opacity(isPanelShown ? 1.0 : 0)

            // Content Overlay
            mainContent()
                .frame(width: mainWidth, height: controlHeight)
                .offset(y: scaled(Constants.Layout.offsetYDefault))
                .opacity(isPanelShown ? 1 : 0)
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.88), value: ShowIOrbs)
        .animation(.spring(response: 0.35, dampingFraction: 0.9), value: state)
        .frame(width: canvasSize.width, height: canvasSize.height)
        .onAppear {
            syncVisualState(animated: false)
        }
        .onChange(of: state) { newValue in
            syncVisualState(animated: true)
        }
    }

    @ViewBuilder
    private func mainContent() -> some View {
        switch state {
        case .error(let failure):
            messageText(
                failure.message,
                fontSize: 13,
                lineLimit: 3,
                minimumScaleFactor: 0.9
            )
            .padding(.horizontal, scaled(24))
        default:
            EmptyView()
        }
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


    private func scaled(_ value: CGFloat) -> CGFloat {
        value
    }

    private func syncVisualState(animated: Bool) {
        let shouldShowPanel: Bool
        let shouldShowIOrbs: Bool

        switch state {
        case .starting, .listening:
            shouldShowPanel = true
            shouldShowIOrbs = true
        case .processing:
            shouldShowPanel = true
            shouldShowIOrbs = false
        default:
            shouldShowPanel = false
            shouldShowIOrbs = true
        }

        if animated {
            isPanelShown = shouldShowPanel
            ShowIOrbs = shouldShowIOrbs
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                isPanelShown = shouldShowPanel
                ShowIOrbs = shouldShowIOrbs
            }
        }
    }

    private func handleCancelAction() {
        switch state {
        case .listening, .starting:
            runSymmetricCloseAnimation(perform: viewModel.cancelActiveCapture)
        case .idle, .error:
            runSymmetricCloseAnimation(perform: viewModel.hidePanel)
        default:
            break
        }
    }

    private func runSymmetricCloseAnimation(perform action: @escaping () -> Void) {
        withAnimation(.spring()) {
            isPanelShown = false
            ShowIOrbs = false
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            action()
        }
    }

    private func handleFinishAction() {
        viewModel.performPrimaryAction()
    }

    private func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }
}

// MARK: - Dedicated Shader Layer
private struct MacDictationShaderLayer: View {
    let state: DictationState
    let mainWidth: CGFloat
    let controlHeight: CGFloat
    let startDate: Date
    let shaderFrameInterval: Double
    let displayLevel: Double

    var body: some View {
        TimelineView(.animation(minimumInterval: shaderFrameInterval, paused: false)) { timeline in
            let elapsed = timeline.date.timeIntervalSince(startDate)
            
            let effectiveLevel: Double = {
                if case .processing = state {
                    return 0.28 + 0.10 * sin(elapsed * 1.7) + 0.05 * sin(elapsed * 3.9)
                } else {
                    return displayLevel
                }
            }()
            
            let colors = currentShaderColors(elapsed: elapsed, effectiveLevel: effectiveLevel)
            
            Capsule().fill(.white)
                .colorEffect(
                    ShaderLibrary.cloudOrbGlassWide(
                        .float2(mainWidth, controlHeight),
                        .float(elapsed),
                        .float(effectiveLevel),
                        .color(colors.top),
                        .color(colors.mid),
                        .color(colors.low)
                    )
                )
                .frame(width: mainWidth, height: controlHeight)
                .allowsHitTesting(false)
        }
    }

    private func currentShaderColors(elapsed: Double, effectiveLevel: Double) -> (top: Color, mid: Color, low: Color) {
        let talk = min(max(effectiveLevel, 0.0), 1.0)
        let breath = talk * talk * (3.0 - 2.0 * talk)
        
        let injection: Double
        let targetTop: (Double, Double, Double)
        let targetMid: (Double, Double, Double)
        let targetLow: (Double, Double, Double)

        switch state {
        case .processing:
            // Combine fake audio breath with a slight base glow boost
            injection = 0.5 + 0.5 * breath
            targetTop = Constants.Colors.topProcessing
            targetMid = Constants.Colors.midProcessing
            targetLow = Constants.Colors.lowProcessing
        case .starting, .listening:
            injection = breath
            targetTop = Constants.Colors.topSpeaking
            targetMid = Constants.Colors.midSpeaking
            targetLow = Constants.Colors.lowSpeaking
        case .result(_):
            injection = 0.4
            targetTop = Constants.Colors.topSpeaking
            targetMid = Constants.Colors.midSpeaking
            targetLow = Constants.Colors.lowSpeaking
        default:
            injection = 0
            targetTop = Constants.Colors.topIdle
            targetMid = Constants.Colors.midIdle
            targetLow = Constants.Colors.lowIdle
        }

        let top = Color(
            red:   lerp(Constants.Colors.topIdle.0, targetTop.0, injection),
            green: lerp(Constants.Colors.topIdle.1, targetTop.1, injection),
            blue:  lerp(Constants.Colors.topIdle.2, targetTop.2, injection)
        )
        let mid = Color(
            red:   lerp(Constants.Colors.midIdle.0, targetMid.0, injection),
            green: lerp(Constants.Colors.midIdle.1, targetMid.1, injection),
            blue:  lerp(Constants.Colors.midIdle.2, targetMid.2, injection)
        )
        let low = Color(
            red:   lerp(Constants.Colors.lowIdle.0, targetLow.0, injection),
            green: lerp(Constants.Colors.lowIdle.1, targetLow.1, injection),
            blue:  lerp(Constants.Colors.lowIdle.2, targetLow.2, injection)
        )
        return (top, mid, low)
    }

    private func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }
}

private struct MacDictationClipboardSurface: View {
    let text: String
    let layout: MacDictationPanelLayout
    let onFinish: () -> Void

    @State private var contentVisible = false

    var body: some View {
        VStack(spacing: 8) {
            Text(text)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.96))
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.horizontal, 24)

            Button(action: onFinish) {
                HStack(spacing: 6) {
                    Image(systemName: "scissors")
                        .font(.system(size: 11, weight: .bold))
                    Text("OK")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background {
                    Capsule()
                        .fill(.white.opacity(0.12))
                        .overlay {
                            Capsule().stroke(.white.opacity(0.1), lineWidth: 0.5)
                        }
                }
            }
            .buttonStyle(.plain)
        }
        .frame(width: layout.panelSize.width, height: layout.panelSize.height, alignment: .center)
        .background {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .glassEffect(.regular)
                .shadow(
                    color: .black.opacity(0.22),
                    radius: 18,
                    y: 10
                )
        }
        .opacity(contentVisible ? 1 : 0)
        .offset(y: contentVisible ? 0 : 8)
        .scaleEffect(contentVisible ? 1 : 0.985)
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.9).delay(0.09)) {
                contentVisible = true
            }
        }
    }
}

private extension Color {
    static let primaryAction = Color(
        red: 179.0 / 255.0,
        green: 190.0 / 255.0,
        blue: 250.0 / 255.0
    )
}
#endif
