#if os(macOS)
import SwiftUI

struct OnboardingModeStep: View {
    @ObservedObject var viewModel: OnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            GroupBox("Privacy Note") {
                VStack(alignment: .leading, spacing: 10) {
                    BulletRow(text: "Login Or BYOK")
//                    BulletRow(text: "Cloud processing is transient and not stored")
//                    BulletRow(text: "You can always use your own API Key")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }

            VStack(alignment: .leading, spacing: 16) {
                OnboardingChoiceCard(
                    title: "Use my own API Key",
                    details: [
                        "Full control"
                    ],
                    buttonTitle: "Use API Key"
                ) {
                    viewModel.chooseOnboardingMode(.apiKey)
                }

                OnboardingChoiceCard(
                    title: "Login to use",
                    details: [
                        "Faster setup",
                    ],
                    buttonTitle: "Login to continue"
                ) {
                    viewModel.chooseOnboardingMode(.managed)
                }
            }

            Spacer()
        }
    }
}

#if DEBUG
#Preview {
    OnboardingModeStep(viewModel: OnboardingViewModel(coordinator: MockOnboardingCoordinator(step: .mode)))
        .frame(width: 440)
        .padding()
}
#endif

#endif
