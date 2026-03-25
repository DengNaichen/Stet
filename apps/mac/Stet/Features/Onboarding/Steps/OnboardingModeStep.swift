#if os(macOS)
    import SwiftUI

    struct OnboardingModeStep: View {
        @ObservedObject var viewModel: OnboardingViewModel

        var body: some View {
            VStack(alignment: .leading, spacing: 20) {
                VStack(spacing: 8) {
                    OnboardingActionButton(
                        title: "Sign In",
                        background: viewModel.onboardingStep == .login
                            ? Color.accentColor
                            : Color.primary.opacity(0.06),
                        foreground: viewModel.onboardingStep == .login
                            ? .white
                            : .primary,
                        strokeColor: viewModel.onboardingStep == .login
                            ? .clear
                            : Color.primary.opacity(0.12),
                        minHeight: 48
                    ) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            viewModel.chooseOnboardingMode(.managed)
                        }
                    }

                    OnboardingActionButton(
                        title: "Use API Key",
                        background: viewModel.onboardingStep == .apiKey
                            ? Color.accentColor
                            : Color.primary.opacity(0.06),
                        foreground: viewModel.onboardingStep == .apiKey
                            ? .white
                            : .primary,
                        strokeColor: viewModel.onboardingStep == .apiKey
                            ? .clear
                            : Color.primary.opacity(0.12),
                        minHeight: 48
                    ) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            viewModel.chooseOnboardingMode(.apiKey)
                        }
                    }
                }

                Spacer()
            }
        }
    }

    #if DEBUG
        #Preview {
            OnboardingModeStep(viewModel: OnboardingViewModel(coordinator: MockOnboardingCoordinator(step: .login)))
                .frame(width: 440)
                .padding()
        }
    #endif

#endif
