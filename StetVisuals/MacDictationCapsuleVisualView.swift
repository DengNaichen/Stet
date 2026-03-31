#if os(macOS)
    import SwiftUI

    private enum MacDictationCapsuleVisualTuning {
        static let orbSpacing: CGFloat = 18.144
        static let orbTravelDistance: CGFloat = 150
        static let orbHiddenScale: CGFloat = 0.84
        static let panelHiddenScale: CGFloat = 0.90
        static let orbRevealDelay: Duration = .milliseconds(130)
        static let closeAnimationDuration: UInt64 = 320_000_000

        static let panelSpring = Animation.spring(response: 0.34, dampingFraction: 0.90)
        static let orbSpring = Animation.spring(response: 0.62, dampingFraction: 0.90)
        static let closeSpring = Animation.spring(response: 0.30, dampingFraction: 0.92)
    }

    public struct MacDictationCapsuleVisualView: View {
        let model: MacDictationCapsuleVisualModel
        let actions: MacDictationCapsuleVisualActions

        @Namespace private var glassNamespace

        @State private var isPanelShown = false
        @State private var showOrbs = true
        @State private var startDate = Date()
        @State private var processingStartDate: Date?
        @State private var orbRevealTask: Task<Void, Never>?

        private var orbFontSize: CGFloat {
            model.controlHeight * 0.6
        }

        private var collapsedOrbOffset: CGFloat {
            (model.mainWidth * 0.5)
                + MacDictationCapsuleVisualTuning.orbSpacing
                + (model.controlHeight * 0.5)
        }

        private var keepsHiddenOrbsCollapsed: Bool {
            switch model.state {
            case .processing, .result:
                return true
            case .hidden, .starting, .listening, .error:
                return false
            }
        }

        private var hiddenLeftOrbOffset: CGFloat {
            keepsHiddenOrbsCollapsed ? collapsedOrbOffset : MacDictationCapsuleVisualTuning.orbTravelDistance
        }

        private var hiddenRightOrbOffset: CGFloat {
            keepsHiddenOrbsCollapsed ? -collapsedOrbOffset : -MacDictationCapsuleVisualTuning.orbTravelDistance
        }

        public init(
            model: MacDictationCapsuleVisualModel,
            actions: MacDictationCapsuleVisualActions
        ) {
            self.model = model
            self.actions = actions
        }

        public var body: some View {
            ZStack {
                ZStack {
                    GlassEffectContainer(spacing: MacDictationCapsuleVisualTuning.orbSpacing) {
                        HStack(spacing: MacDictationCapsuleVisualTuning.orbSpacing) {
                            Button(action: handleDismissAction) {
                                Image(systemName: "xmark")
                                    .font(.system(size: orbFontSize, weight: .bold))
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .frame(width: model.controlHeight, height: model.controlHeight)
                            .glassEffect(.regular.tint(nil))
                            .glassEffectID("cancel", in: glassNamespace)
                            .opacity(isPanelShown && showOrbs ? 1 : 0)
                            .offset(x: isPanelShown && showOrbs ? 0 : hiddenLeftOrbOffset)
                            .scaleEffect(isPanelShown && showOrbs ? 1 : MacDictationCapsuleVisualTuning.orbHiddenScale)
                            .allowsHitTesting(isPanelShown && showOrbs)

                            Capsule()
                                .frame(width: model.mainWidth, height: model.controlHeight)
                                .glassEffect(.regular.tint(nil))
                                .glassEffectID("main", in: glassNamespace)

                            Button(action: actions.onConfirm) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: orbFontSize, weight: .bold))
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .frame(width: model.controlHeight, height: model.controlHeight)
                            .glassEffect(.regular.tint(nil))
                            .glassEffectID("done", in: glassNamespace)
                            .opacity(isPanelShown && showOrbs ? 1 : 0)
                            .offset(x: isPanelShown && showOrbs ? 0 : hiddenRightOrbOffset)
                            .scaleEffect(isPanelShown && showOrbs ? 1 : MacDictationCapsuleVisualTuning.orbHiddenScale)
                            .allowsHitTesting(isPanelShown && showOrbs)
                        }
                    }

                    MacDictationShaderLayer(
                        state: model.state,
                        mainWidth: model.mainWidth,
                        controlHeight: model.controlHeight,
                        startDate: processingStartDate ?? startDate,
                        shaderFrameInterval: model.shaderFrameInterval,
                        signals: model.signals,
                        shaderTheme: model.shaderTheme,
                        isPaused: model.isShaderPaused
                    )
                }
                .opacity(isPanelShown ? 1.0 : 0)

                mainContent()
                    .frame(width: model.mainWidth, height: model.controlHeight)
                    .offset(y: MacDictationPanelConstants.Layout.offsetYDefault)
                    .opacity(isPanelShown ? 1 : 0)
            }
            .scaleEffect(isPanelShown ? 1.0 : MacDictationCapsuleVisualTuning.panelHiddenScale)
            .frame(width: model.panelSize.width, height: model.panelSize.height)
            .onAppear {
                syncVisualState(animated: true)
            }
            .onChange(of: model.state) { _, newState in
                // Reset processing timer immediately when entering processing state
                if case .processing = newState {
                    processingStartDate = Date()
                } else {
                    processingStartDate = nil
                }
                syncVisualState(animated: true)
            }
            .onDisappear {
                orbRevealTask?.cancel()
                orbRevealTask = nil
            }
        }

        @ViewBuilder
        private func mainContent() -> some View {
            if let message = model.overlayMessage {
                Text(message)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.96))
                    .lineLimit(3)
                    .minimumScaleFactor(0.9)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
                    .shadow(color: .black.opacity(0.16), radius: 10, y: 4)
                    .padding(.horizontal, 24)
            } else {
                EmptyView()
            }
        }

        private func syncVisualState(animated: Bool) {
            orbRevealTask?.cancel()
            orbRevealTask = nil

            if animated {
                if model.shouldShowPanel {
                    if !isPanelShown {
                        startDate = Date()
                        processingStartDate = nil
                    }

                    withAnimation(MacDictationCapsuleVisualTuning.panelSpring) {
                        isPanelShown = true
                    }

                    if model.shouldShowOrbs {
                        if !showOrbs {
                            showOrbs = false
                            orbRevealTask = Task { @MainActor in
                                try? await Task.sleep(for: MacDictationCapsuleVisualTuning.orbRevealDelay)
                                guard !Task.isCancelled else { return }
                                withAnimation(MacDictationCapsuleVisualTuning.orbSpring) {
                                    showOrbs = true
                                }
                                orbRevealTask = nil
                            }
                        }
                    } else {
                        withAnimation(MacDictationCapsuleVisualTuning.orbSpring) {
                            showOrbs = false
                        }
                    }
                } else {
                    withAnimation(MacDictationCapsuleVisualTuning.closeSpring) {
                        showOrbs = false
                        isPanelShown = false
                    }
                }
            } else {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    isPanelShown = model.shouldShowPanel
                    showOrbs = model.shouldShowOrbs
                }
            }
        }

        private func handleDismissAction() {
            orbRevealTask?.cancel()
            orbRevealTask = nil

            withAnimation(MacDictationCapsuleVisualTuning.closeSpring) {
                isPanelShown = false
                showOrbs = false
            }

            Task { @MainActor in
                try? await Task.sleep(nanoseconds: MacDictationCapsuleVisualTuning.closeAnimationDuration)
                actions.onDismiss()
            }
        }
    }
#endif
