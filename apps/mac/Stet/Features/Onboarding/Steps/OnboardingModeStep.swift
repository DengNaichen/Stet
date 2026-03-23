#if os(macOS)
import SwiftUI

struct OnboardingModeStep: View {
    @ObservedObject var viewModel: OnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
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
