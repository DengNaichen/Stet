#if os(macOS)
import SwiftUI

struct OnboardingWelcomeStep: View {
    @ObservedObject var viewModel: OnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    BulletRow(text: "Native Mac App")
                    BulletRow(text: "Preserve your natural expression")
                    BulletRow(text: "Privacy first: Login or bring your own API Key")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }

            Spacer()

            HStack {
                Spacer()

                OnboardingActionButton(title: "Continue", minHeight: 48) {
                    viewModel.continueOnboarding()
                }
            }
        }
    }
}

#if DEBUG
#Preview {
    OnboardingWelcomeStep(viewModel: OnboardingViewModel(coordinator: MockOnboardingCoordinator(step: .welcome)))
        .frame(width: 440)
        .padding()
}
#endif

#endif
