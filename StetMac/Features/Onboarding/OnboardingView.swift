#if os(macOS)
    import StetVisuals
    import SwiftUI

    struct OnboardingView: View {
        @StateObject private var viewModel: OnboardingViewModel
        @StateObject private var appearanceViewModel: MacAppearanceSettingsViewModel
        @State private var showWelcome: Bool

        init(appModel: any MacPermissionsCoordinating) {
            let vm = OnboardingViewModel(coordinator: appModel)
            _viewModel = StateObject(wrappedValue: vm)
            _appearanceViewModel = StateObject(wrappedValue: .shared)
            _showWelcome = State(initialValue: appModel.onboardingStep == .language)
        }

        init(viewModel: OnboardingViewModel, showWelcome: Bool = false) {
            _viewModel = StateObject(wrappedValue: viewModel)
            _appearanceViewModel = StateObject(wrappedValue: .shared)
            _showWelcome = State(initialValue: showWelcome)
        }

        private var activeTheme: MacDictationVisualTheme {
            if viewModel.onboardingStep == .appearance {
                return viewModel.onboardingPreviewTheme
            }
            return appearanceViewModel.shaderTheme
        }

        private var activeShaderTheme: MacDictationShaderTheme {
            MacDictationShaderTheme(rawValue: activeTheme.rawValue) ?? .watercolor
        }

        private var isShowingWelcome: Bool {
            showWelcome && viewModel.onboardingStep == .language
        }

        var body: some View {
            ZStack {
                ambientBackground

                VStack(spacing: 0) {
                    headerChrome

                    stepContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .animation(
                            .easeOut(duration: 0.22),
                            value: isShowingWelcome ? 0 : viewModel.onboardingStep.rawValue
                        )
                }
            }
            .frame(width: OnboardingMetrics.windowWidth, height: OnboardingMetrics.windowHeight)
            .background(MacUI.LinearSurfaces.detailCanvas)
            .onAppear {
                appearanceViewModel.load()
                viewModel.selectOnboardingAppearanceTheme(appearanceViewModel.shaderTheme)
            }
        }

        private var ambientBackground: some View {
            let swatches = OnboardingPalette.themeSwatches(for: activeTheme)
            let primaryTint = swatches.last ?? MacUI.LinearBrand.accent
            let secondaryTint = swatches.first ?? MacUI.LinearBrand.accent

            return ZStack {
                MacUI.LinearSurfaces.detailCanvas

                RadialGradient(
                    colors: [primaryTint.opacity(0.11), .clear],
                    center: UnitPoint(x: 0.5, y: 0.08),
                    startRadius: 10,
                    endRadius: 270
                )

                RadialGradient(
                    colors: [secondaryTint.opacity(0.10), .clear],
                    center: UnitPoint(x: 0.78, y: 0.16),
                    startRadius: 10,
                    endRadius: 210
                )
            }
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.4), value: activeTheme)
        }

        private var headerChrome: some View {
            HStack {
                Spacer()

                if !isShowingWelcome && viewModel.onboardingStep != .done {
                    HStack(spacing: 6) {
                        ForEach(1...5, id: \.self) { index in
                            let current = viewModel.onboardingStep.progressIndex
                            Capsule(style: .continuous)
                                .fill(progressDotColor(for: index, current: current))
                                .frame(width: index == current ? 30 : 18, height: 4)
                                .animation(
                                    .spring(response: 0.34, dampingFraction: 0.8),
                                    value: current
                                )
                        }
                    }
                    .transition(.opacity)
                }

                Spacer()
            }
            .frame(height: OnboardingMetrics.headerHeight)
        }

        private func progressDotColor(for index: Int, current: Int) -> Color {
            if index == current {
                return MacUI.LinearBrand.accent
            }
            if index < current {
                return MacUI.Foreground.primary.opacity(0.42)
            }
            return MacUI.LinearSurfaces.hairlineStrong
        }

        @ViewBuilder
        private var stepContent: some View {
            if isShowingWelcome {
                welcomeStep
            } else {
                switch viewModel.onboardingStep {
                case .language:
                    OnboardingLanguageStep(
                        viewModel: viewModel,
                        onBackToWelcome: {
                            withAnimation(.easeOut(duration: 0.22)) {
                                showWelcome = true
                            }
                        }
                    )
                case .permissions:
                    OnboardingPermissionsStep(viewModel: viewModel)
                case .shortcut:
                    OnboardingShortcutStep(viewModel: viewModel)
                case .firstSuccess:
                    OnboardingFirstSuccessStep(viewModel: viewModel)
                case .appearance:
                    OnboardingAppearanceStep(
                        viewModel: viewModel,
                        appearanceViewModel: appearanceViewModel
                    )
                case .done:
                    OnboardingDoneStep(
                        viewModel: viewModel,
                        theme: activeShaderTheme
                    )
                }
            }
        }

        private var welcomeStep: some View {
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    Spacer(minLength: 8)

                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        (OnboardingPalette.themeSwatches(for: activeTheme).last
                                            ?? MacUI.LinearBrand.accent).opacity(0.24),
                                        .clear,
                                    ],
                                    center: .center,
                                    startRadius: 8,
                                    endRadius: 68
                                )
                            )
                            .frame(width: 136, height: 136)

                        MacDictationCapsulePreviewView(
                            theme: activeShaderTheme,
                            scale: 1.48
                        )
                        .shadow(color: Color.black.opacity(0.14), radius: 22, x: 0, y: 10)
                    }
                    .padding(.bottom, 22)

                    Text("Speak naturally.\nType effortlessly.")
                        .font(.system(size: 26, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(MacUI.Foreground.primary)
                        .lineSpacing(2)

                    Text(
                        "Private, on-device voice dictation that works in any macOS app — press one shortcut, speak, and watch clean text appear."
                    )
                    .font(.system(size: 13.5))
                    .foregroundStyle(MacUI.Foreground.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2.5)
                    .frame(maxWidth: 390)
                    .padding(.top, 10)

                    HStack(spacing: 8) {
                        OnboardingFeaturePill(title: "On-device", systemImage: "lock.shield")
                        OnboardingFeaturePill(title: "Local engine", systemImage: "bolt")
                        OnboardingFeaturePill(title: "Any text field", systemImage: "text.cursor")
                    }
                    .padding(.top, 22)

                    Spacer(minLength: 12)
                }
                .padding(.horizontal, OnboardingMetrics.contentHorizontalPadding)

                OnboardingFooterBar {
                    Text("Takes about 1 minute")
                        .font(.system(size: 11.5))
                        .foregroundStyle(MacUI.LinearSurfaces.mutedInk)
                } trailing: {
                    OnboardingPrimaryButton("Get Started") {
                        withAnimation(.easeOut(duration: 0.22)) {
                            showWelcome = false
                        }
                    }
                }
            }
        }
    }

    #if DEBUG
        @MainActor
        private func makeOnboardingPreview(
            step: MacOnboardingStep,
            showWelcome: Bool = false,
            mode: MacOnboardingMode? = nil
        ) -> OnboardingView {
            let coordinator = MockOnboardingCoordinator(step: step, mode: mode)
            let viewModel = OnboardingViewModel(
                coordinator: coordinator,
                credentialValidationService: PreviewOnboardingAPIKeyValidationService()
            )

            return OnboardingView(viewModel: viewModel, showWelcome: showWelcome)
        }

        #Preview("Interactive Flow") {
            makeOnboardingPreview(step: .language, showWelcome: true)
        }

        #Preview("Language") {
            makeOnboardingPreview(step: .language)
        }

        #Preview("Permissions") {
            makeOnboardingPreview(step: .permissions)
        }

        #Preview("Shortcut") {
            makeOnboardingPreview(step: .shortcut)
        }

        #Preview("First Success") {
            makeOnboardingPreview(step: .firstSuccess)
        }

        #Preview("Appearance") {
            makeOnboardingPreview(step: .appearance)
        }

        #Preview("Done") {
            makeOnboardingPreview(step: .done)
        }
    #endif
#endif
