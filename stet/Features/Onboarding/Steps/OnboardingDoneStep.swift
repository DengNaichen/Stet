#if os(macOS)
    import SwiftUI

    struct OnboardingDoneStep: View {
        @ObservedObject var viewModel: OnboardingViewModel

        var body: some View {
            VStack(alignment: .leading, spacing: 18) {
                Text("Appearance")
                    .font(.title2.weight(.semibold))

                Text("Choose your preferred theme")
                    .font(.body)
                    .foregroundStyle(.secondary)

                Spacer()

                HStack {
                    OnboardingActionButton(
                        title: "Finish",
                        minHeight: 48
                    ) {
                        viewModel.finishOnboarding()
                    }

                    Spacer()
                }
            }
        }
    }

    #if DEBUG
        #Preview {
            OnboardingDoneStep(viewModel: OnboardingViewModel(coordinator: MockOnboardingCoordinator(step: .done)))
                .frame(width: 440)
                .padding()
        }
    #endif

#endif
