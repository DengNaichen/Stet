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

        var body: some View {
            ZStack {
                backgroundLayer

                HStack(spacing: 0) {
                    leftPanel

                    separator

                    rightPanel
                        .frame(width: 400, height: 680)
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.08))
                }
                .frame(width: 900, height: 680)
                .background(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.66))
                )
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.20), radius: 26, x: 0, y: 12)
            }
            .frame(width: 900, height: 680)
            .background(rootBackground)
        }

        private var backgroundLayer: some View {
            ZStack {
                rootBackground

                RadialGradient(
                    colors: [Color.accentColor.opacity(0.18), .clear],
                    center: .topLeading,
                    startRadius: 20,
                    endRadius: 320
                )
                .blur(radius: 2)
                .offset(x: -220, y: -180)

                RadialGradient(
                    colors: [Color.blue.opacity(0.16), .clear],
                    center: .topTrailing,
                    startRadius: 20,
                    endRadius: 280
                )
                .blur(radius: 2)
                .offset(x: 240, y: -160)

                RadialGradient(
                    colors: [Color.purple.opacity(0.14), .clear],
                    center: .bottomLeading,
                    startRadius: 20,
                    endRadius: 260
                )
                .blur(radius: 2)
                .offset(x: -200, y: 200)
            }
            .ignoresSafeArea()
        }

        private var rootBackground: some View {
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color(nsColor: .controlBackgroundColor).opacity(0.95),
                    Color(nsColor: .windowBackgroundColor),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }

        private var leftPanel: some View {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center, spacing: 12) {
                    OnboardingPill(
                        text: "Stet onboarding", systemImage: "sparkles", tint: .accentColor)

                    Spacer(minLength: 0)

                    Text("Step \(viewModel.onboardingStep.progressIndex) of 5")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text(titleText)
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .fixedSize(horizontal: false, vertical: true)

                    Text(subtitleText)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                progressStrip

                stepContent
                    .groupBoxStyle(CleanGroupBoxStyle())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                footer
            }
            .padding(28)
            .frame(width: 499, height: 680, alignment: .topLeading)
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
            HStack(spacing: 8) {
                ForEach(1...5, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(
                            index <= viewModel.onboardingStep.progressIndex
                                ? Color.accentColor : Color.secondary.opacity(0.20)
                        )
                        .frame(height: 6)
                }
            }
        }

        @ViewBuilder
        private var stepContent: some View {
            switch viewModel.onboardingStep {
            case .mode, .apiKey:
                OnboardingModeStep(viewModel: viewModel)
            case .login:
                OnboardingLoginStep(viewModel: viewModel)
            case .permissions:
                OnboardingPermissionsStep(viewModel: viewModel)
            case .shortcut:
                OnboardingShortcutStep(viewModel: viewModel)
            case .firstSuccess:
                OnboardingFirstSuccessStep(viewModel: viewModel)
            case .done:
                OnboardingDoneStep(viewModel: viewModel)
            }
        }

        @ViewBuilder
        private var rightPanel: some View {
            if viewModel.onboardingStep == .apiKey {
                OnboardingAPIKeyStep(viewModel: viewModel)
                    .padding(40)
            } else {
                OnboardingVisualPanel(step: viewModel.onboardingStep, viewModel: viewModel)
                    .padding(.vertical, 0)
                    .padding(.trailing, 0)
                    .padding(.leading, 0)
            }
        }

        private var footer: some View {
            HStack(spacing: 12) {
                Spacer()

                Text(titleBadgeText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }

        private var titleBadgeText: String {
            switch viewModel.onboardingStep {
            case .mode, .apiKey:
                return "Same flow, clearer layout"
            case .login:
                return "Managed sign-in"
            case .permissions:
                return "Permission gate"
            case .shortcut:
                return "Shortcut setup"
            case .firstSuccess:
                return "First success check"
            case .done:
                return "Ready"
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
