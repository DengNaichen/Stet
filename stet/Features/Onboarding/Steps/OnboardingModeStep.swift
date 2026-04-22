#if os(macOS)
    import SwiftUI

    struct OnboardingModeStep: View {
        @ObservedObject var viewModel: OnboardingViewModel

        var body: some View {
            VStack(alignment: .leading, spacing: 20) {
                VStack(spacing: 8) {
                    OnboardingActionButton(
                        title: "Sign In",
                        background: viewModel.onboardingMode == .managed
                            ? Color.accentColor
                            : Color.primary.opacity(0.06),
                        foreground: viewModel.onboardingMode == .managed
                            ? .white
                            : .primary,
                        strokeColor: viewModel.onboardingMode == .managed
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
                        background: viewModel.onboardingMode == .apiKey
                            ? Color.accentColor
                            : Color.primary.opacity(0.06),
                        foreground: viewModel.onboardingMode == .apiKey
                            ? .white
                            : .primary,
                        strokeColor: viewModel.onboardingMode == .apiKey
                            ? .clear
                            : Color.primary.opacity(0.12),
                        minHeight: 48
                    ) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            viewModel.chooseOnboardingMode(.apiKey)
                        }
                    }
                }

                if viewModel.onboardingStep == .login {
                    Text("New users will be assigned 10K words for a free trial.")
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
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
