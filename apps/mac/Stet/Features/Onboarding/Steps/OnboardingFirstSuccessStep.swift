#if os(macOS)
import SwiftUI

struct OnboardingFirstSuccessStep: View {
    @ObservedObject var viewModel: OnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            GroupBox("Example") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Example Input")
                        .font(.headline)

                    Text("Tomorrow afternoon, uh wait, 3 PM, help me book it")
                        .foregroundStyle(.secondary)

                    if let firstSuccessPreviewText = viewModel.firstSuccessPreviewText {
                        MessageBanner(text: "It worked: \(firstSuccessPreviewText)", role: .success)
                    } else if let firstSuccessFailureMessage = viewModel.firstSuccessFailureMessage {
                        MessageBanner(text: firstSuccessFailureMessage, role: .error)
                    }
                }
                .padding(8)
            }

            Spacer()

            HStack {
                Button("Back") {
                    viewModel.retreatOnboarding()
                }

                Spacer()

                if viewModel.canSkipFirstSuccessOnboarding && !viewModel.canContinueFirstSuccessOnboarding {
                    Button("Skip for now and try later") {
                        viewModel.continueOnboarding()
                    }
                }

                Button("Continue") {
                    viewModel.continueOnboarding()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canContinueFirstSuccessOnboarding && !viewModel.canSkipFirstSuccessOnboarding)
            }
        }
    }
}

#if DEBUG
#Preview {
    OnboardingFirstSuccessStep(viewModel: OnboardingViewModel(coordinator: MockOnboardingCoordinator(step: .firstSuccess)))
        .frame(width: 440)
        .padding()
}
#endif

#endif
