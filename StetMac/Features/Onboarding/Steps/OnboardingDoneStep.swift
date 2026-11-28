#if os(macOS)
    import StetVisuals
    import SwiftUI

    struct OnboardingDoneStep: View {
        @ObservedObject var viewModel: OnboardingViewModel
        var theme: MacDictationShaderTheme = .watercolor

        var body: some View {
            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    Spacer(minLength: 12)

                    MacDictationCapsulePreviewView(
                        theme: theme,
                        scale: 1.4
                    )
                    .shadow(color: Color.black.opacity(0.14), radius: 20, x: 0, y: 8)
                    .padding(.bottom, 8)

                    Text("You're all set")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(MacUI.Foreground.primary)

                    Text("Stet now lives quietly in your menu bar. Press your shortcut anywhere you can type text.")
                        .font(.system(size: 13.5))
                        .foregroundStyle(MacUI.Foreground.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 380)

                    Spacer(minLength: 12)
                }
                .padding(.horizontal, OnboardingMetrics.contentHorizontalPadding)

                OnboardingFooterBar {
                    EmptyView()
                } trailing: {
                    OnboardingPrimaryButton("Finish") {
                        viewModel.finishOnboarding()
                    }
                }
            }
        }
    }

    #if DEBUG
        #Preview {
            OnboardingDoneStep(
                viewModel: OnboardingViewModel(coordinator: MockOnboardingCoordinator(step: .done))
            )
            .frame(width: OnboardingMetrics.windowWidth, height: 500)
        }
    #endif
#endif
