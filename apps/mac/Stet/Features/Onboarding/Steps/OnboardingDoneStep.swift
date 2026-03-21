#if os(macOS)
import SwiftUI

struct OnboardingDoneStep: View {
    @ObservedObject var viewModel: OnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            GroupBox("Overview") {
                VStack(alignment: .leading, spacing: 12) {
                    SummaryRow(title: "Shortcut", value: viewModel.shortcutSummaryText)
                    SummaryRow(
                        title: "Current Mode",
                        value: viewModel.onboardingMode == .apiKey ? "API Key" : "Logged In"
                    )
                    SummaryRow(
                        title: "Permissions",
                        value: viewModel.hasRequiredPermissions ? "Enabled" : "Check required"
                    )
                }
                .padding(8)
            }

            Spacer()

            HStack {
                Spacer()

                Button("Get Started") {
                    viewModel.finishOnboarding()
                }
                .buttonStyle(.borderedProminent)
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
