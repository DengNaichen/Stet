#if os(macOS)
    import SwiftUI

    struct OnboardingAppearanceStep: View {
        @ObservedObject var viewModel: OnboardingViewModel
        @ObservedObject var appearanceViewModel: MacAppearanceSettingsViewModel

        var body: some View {
            VStack(alignment: .leading, spacing: 18) {
                Text(statusText)
                    .font(.body)
                    .foregroundStyle(appearanceViewModel.hasAppliedSelectedTheme ? .green : .secondary)

                Spacer()

                HStack {
                    OnboardingBackButton { viewModel.retreatOnboarding() }

                    Spacer()

                    OnboardingActionButton(
                        title: "Finish",
                        isEnabled: appearanceViewModel.hasAppliedSelectedTheme,
                        minHeight: 48
                    ) {
                        viewModel.finishOnboarding()
                    }
                }
            }
        }

        private var statusText: String {
            if appearanceViewModel.hasAppliedSelectedTheme {
                return "\(appearanceViewModel.shaderTheme.title) is applied. You can finish now."
            }

            return "Choose a theme on the right, apply it, then finish."
        }
    }

    #if DEBUG
        #Preview {
            OnboardingAppearanceStep(
                viewModel: OnboardingViewModel(
                    coordinator: MockOnboardingCoordinator(step: .appearance)
                ),
                appearanceViewModel: .shared
            )
            .frame(width: 440)
            .padding()
        }
    #endif

#endif
