#if os(macOS)
    import SwiftUI

    struct OnboardingFirstSuccessStep: View {
        @ObservedObject var viewModel: OnboardingViewModel
        @State private var draftText = ""
        @FocusState private var isDraftFocused: Bool

        var body: some View {
            VStack(alignment: .leading, spacing: 18) {
                Text("Click into the text box on the right, then use your hotkey to test voice input.")
                    .font(.body)
                    .foregroundStyle(.secondary)

                if let firstSuccessPreviewText = viewModel.firstSuccessPreviewText {
                    MessageBanner(text: "It worked: \(firstSuccessPreviewText)", role: .success)
                } else if let firstSuccessFailureMessage = viewModel.firstSuccessFailureMessage {
                    MessageBanner(text: firstSuccessFailureMessage, role: .error)
                }

                Spacer()

                HStack {
                    OnboardingBackButton { viewModel.retreatOnboarding() }

                    Spacer()

                    if viewModel.canSkipFirstSuccessOnboarding && !viewModel.canContinueFirstSuccessOnboarding {
                        OnboardingActionButton(
                            title: "Skip for now and try later",
                            background: Color.white.opacity(0.10),
                            foreground: .primary,
                            strokeColor: Color.white.opacity(0.10),
                            minHeight: 46
                        ) {
                            viewModel.continueOnboarding()
                        }
                    }

                    OnboardingActionButton(
                        title: "Continue",
                        isEnabled: viewModel.canContinueFirstSuccessOnboarding
                            || viewModel.canSkipFirstSuccessOnboarding,
                        minHeight: 48
                    ) {
                        viewModel.continueOnboarding()
                    }
                }
            }
        }
    }

    #if DEBUG
        #Preview {
            OnboardingFirstSuccessStep(
                viewModel: OnboardingViewModel(coordinator: MockOnboardingCoordinator(step: .firstSuccess))
            )
            .frame(width: 440)
            .padding()
        }
    #endif

#endif
