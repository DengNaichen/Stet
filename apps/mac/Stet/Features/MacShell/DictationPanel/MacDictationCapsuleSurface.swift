#if os(macOS)
import SwiftUI

struct MacDictationCapsuleSurface: View {
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
        let easedLevel = pow(normalizedRecordingLevel, MacDictationPanelConstants.VoiceReactivity.easedPower)

        switch state {
        case .idle:
            return MacDictationPanelConstants.VoiceReactivity.levelBaseIdle
        case .starting:
            return min(MacDictationPanelConstants.VoiceReactivity.levelMaxStarting, MacDictationPanelConstants.VoiceReactivity.levelBaseStarting + easedLevel * MacDictationPanelConstants.VoiceReactivity.levelMultStarting)
        case .listening:
            return min(MacDictationPanelConstants.VoiceReactivity.levelMaxListening, MacDictationPanelConstants.VoiceReactivity.levelBaseListening + easedLevel * MacDictationPanelConstants.VoiceReactivity.levelMultListening)
        case .processing:
            return MacDictationPanelConstants.VoiceReactivity.levelBaseProcessing
        case .result(_):
            return MacDictationPanelConstants.VoiceReactivity.levelBaseResult
        default:
            return 0
        }
    }

    private var mainWidth: CGFloat {
        switch state {
        case .idle:
            scaled(MacDictationPanelConstants.Layout.mainWidthIdle)
        case .starting:
            scaled(MacDictationPanelConstants.Layout.mainWidthStarting)
        case .listening:
            scaled(MacDictationPanelConstants.Layout.mainWidthListening)
        case .processing:
            scaled(MacDictationPanelConstants.Layout.mainWidthProcessing)
        case .result(_):
            scaled(MacDictationPanelConstants.Layout.mainWidthResult)
        case .error(_):
            scaled(MacDictationPanelConstants.Layout.mainWidthError)
        case .clipboardPending(_):
            scaled(200)
        default:
            scaled(200)
        }
    }

    private var controlHeight: CGFloat {
        scaled(MacDictationPanelConstants.Layout.controlHeight)
    }

    private var shaderFrameInterval: Double {
        MacDictationPanelConstants.VoiceReactivity.shaderFrameIntervalActive
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
                .offset(y: scaled(MacDictationPanelConstants.Layout.offsetYDefault))
                .opacity(isPanelShown ? 1 : 0)
        }
        .scaleEffect(isPanelShown ? 1.0 : 0.85)
        .animation(.spring(response: 0.28, dampingFraction: 0.88), value: ShowIOrbs)
        .animation(.spring(response: 0.35, dampingFraction: 0.9), value: state)
        .frame(width: canvasSize.width, height: canvasSize.height)
        .onAppear {
            syncVisualState(animated: true)
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
            shouldShowIOrbs = false
        }

        if animated {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                isPanelShown = shouldShowPanel
                ShowIOrbs = shouldShowIOrbs
            }
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
#endif
