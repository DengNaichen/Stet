#if os(macOS)
    import SwiftUI

    struct OnboardingView: View {
        @StateObject private var viewModel: OnboardingViewModel

        init(appModel: any MacPermissionsCoordinating) {
            _viewModel = StateObject(wrappedValue: OnboardingViewModel(coordinator: appModel))
        }

        init(viewModel: OnboardingViewModel) {
            _viewModel = StateObject(wrappedValue: viewModel)
        }

        // MARK: - Layout constants
        // Outer window: 1280 × 720  (16:9)
        private let windowWidth:  CGFloat = 1280
        private let windowHeight: CGFloat = 720
        // Inner card:   960 × 540  (16:9)
        private let cardWidth:    CGFloat = 960
        private let cardHeight:   CGFloat = 540
        // Golden ratio split (φ ≈ 1.618): left ≈ 367, right ≈ 592
        private let φ: CGFloat = 1.618
        private var rightPanelWidth: CGFloat { (cardWidth * φ / (1 + φ)).rounded() }

        var body: some View {
            ZStack {
                // ── Background image placeholder ──────────────────────────
                // Replace Color.white with Image("your-asset") when ready.
                Color.white
                    .ignoresSafeArea()

                // ── Floating card ─────────────────────────────────────────
                HStack(spacing: 0) {
                    leftPanel

                    separator

                    rightPanel
                        .frame(width: rightPanelWidth, height: cardHeight)
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.08))
                }
                .frame(width: cardWidth, height: cardHeight)
                .background(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.80))
                )
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.18), radius: 40, x: 0, y: 16)
                // ── Progress strip on top border ──────────────────────────
                .overlay(alignment: .top) {
                    progressStrip
                        .offset(y: -16) // straddles the top edge of the card
                }
            }
            .frame(width: windowWidth, height: windowHeight)
        }

        private var leftPanel: some View {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(titleText)
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .fixedSize(horizontal: false, vertical: true)

                    Text(subtitleText)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                stepContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(28)
            .frame(width: cardWidth - rightPanelWidth - 1, height: cardHeight, alignment: .topLeading)
            .background(
                LinearGradient(
                    colors: [
                        Color(nsColor: .controlBackgroundColor).opacity(0.90),
                        Color(nsColor: .windowBackgroundColor).opacity(0.94),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }

        private var separator: some View {
            LinearGradient(
                colors: [
                    Color.white.opacity(0.02),
                    Color.white.opacity(0.18),
                    Color.white.opacity(0.02),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(width: 1)
        }

        private var progressStrip: some View {
            HStack(spacing: 6) {
                ForEach(1...5, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(
                            index <= viewModel.onboardingStep.progressIndex
                                ? Color.accentColor : Color.black.opacity(0.12)
                        )
                        .frame(width: 28, height: 4)
                        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: viewModel.onboardingStep.progressIndex)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule(style: .continuous)
                    .fill(.white)
                    .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 2)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
            )
        }

        @ViewBuilder
        private var stepContent: some View {
            switch viewModel.onboardingStep {
            case .mode, .apiKey, .login:
                OnboardingModeStep(viewModel: viewModel)
            case .permissions:
                OnboardingPermissionsStep(viewModel: viewModel)
            case .shortcut:
                OnboardingShortcutStep(viewModel: viewModel)
            case .firstSuccess:
                OnboardingFirstSuccessStep(viewModel: viewModel)
            case .appearance:
                OnboardingAppearanceStep(viewModel: viewModel)
            case .done:
                OnboardingDoneStep(viewModel: viewModel)
            }
        }

        @ViewBuilder
        private var rightPanel: some View {
            switch viewModel.onboardingStep {
            case .apiKey:
                OnboardingAPIKeyStep(viewModel: viewModel)
                    .padding(40)
            case .login:
                OnboardingLoginStep(viewModel: viewModel)
                    .padding(40)
            case .mode:
                Color.clear
            case .permissions, .shortcut, .firstSuccess, .appearance, .done:
                OnboardingVisualPanel(step: viewModel.onboardingStep, viewModel: viewModel)
            }
        }


        private var titleText: String {
            switch viewModel.onboardingStep {
            case .mode, .apiKey:
                return "Choose how you start"
            case .login:
                return "Login to continue"
            case .permissions:
                return "One more step to get started"
            case .shortcut:
                return "Set your speaking shortcut"
            case .firstSuccess:
                return "Try saying something"
            case .appearance:
                return "Choose your theme"
            case .done:
                return "You're all set"
            }
        }

        private var subtitleText: String {
            switch viewModel.onboardingStep {
            case .mode:
                return
                    "Choose your access method first. Permissions, shortcuts, and initial setup will follow automatically."
            case .apiKey:
                return "Select a provider and enter your API Key to proceed."
            case .login:
                return "Login is only used to enable managed services and sync settings."
            case .permissions:
                return
                    "Grant microphone and input control permissions so Stet can record and type text back into your apps."
            case .shortcut:
                return "Choose the shortcut you want to use for dictation."
            case .firstSuccess:
                return
                    "Hold the shortcut and speak naturally. We'll preserve your intent while performing necessary cleanup."
            case .appearance:
                return "Customize the look and feel of your app."
            case .done:
                return "Hold your shortcut and start speaking anywhere you can type text."
            }
        }
    }

    #if DEBUG
        @MainActor
        private func makeOnboardingPreview(
            step: MacOnboardingStep,
            mode: MacOnboardingMode? = nil
        ) -> OnboardingView {
            let coordinator = MockOnboardingCoordinator(step: step, mode: mode)
            let viewModel = OnboardingViewModel(
                coordinator: coordinator,
                supabase: PreviewOnboardingSupabaseService(),
                apiKeyValidationService: PreviewOnboardingAPIKeyValidationService()
            )

            if step == .apiKey {
                viewModel.apiKey = "sk-preview"
            }

            if step == .login {
                viewModel.email = "preview@stet.app"
                viewModel.password = "password"
            }

            return OnboardingView(viewModel: viewModel)
        }

        #Preview("Interactive Flow") {
            makeOnboardingPreview(step: .mode)
        }

        #Preview("Mode") {
            makeOnboardingPreview(step: .mode)
        }

        #Preview("API Key") {
            makeOnboardingPreview(step: .apiKey, mode: .apiKey)
        }

        #Preview("Login") {
            makeOnboardingPreview(step: .login, mode: .managed)
        }

        #Preview("Permissions") {
            makeOnboardingPreview(step: .permissions, mode: .managed)
        }

        #Preview("Shortcut") {
            makeOnboardingPreview(step: .shortcut, mode: .managed)
        }

        #Preview("First Success") {
            makeOnboardingPreview(step: .firstSuccess, mode: .managed)
        }

        #Preview("Done") {
            makeOnboardingPreview(step: .done, mode: .managed)
        }
    #endif

#endif
