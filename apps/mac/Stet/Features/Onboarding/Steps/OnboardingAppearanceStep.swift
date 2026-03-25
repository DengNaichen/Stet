#if os(macOS)
    import SwiftUI

    struct OnboardingAppearanceStep: View {
        @ObservedObject var viewModel: OnboardingViewModel

        var body: some View {
            VStack(alignment: .leading, spacing: 18) {
                Text("You can adjust the capsule theme later in Settings.")
                    .font(.body)
                    .foregroundStyle(.secondary)

                Spacer()

                    HStack {
                        OnboardingBackButton { viewModel.retreatOnboarding() }

                        Spacer()

                        OnboardingActionButton(
                            title: "Finish",
                            minHeight: 48
                        ) {
                            viewModel.finishOnboarding()
                        }
                    }
                }
            }
        }

    #if DEBUG
        #Preview {
            OnboardingAppearanceStep(
                viewModel: OnboardingViewModel(
                    coordinator: MockOnboardingCoordinator(step: .appearance)
                )
            )
            .frame(width: 440)
            .padding()
        }
    #endif

#endif
