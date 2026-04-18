#if os(macOS)
    import SwiftUI

    struct OnboardingLoginStep: View {
        @ObservedObject var viewModel: OnboardingViewModel

        var body: some View {
            VStack(alignment: .center, spacing: 18) {
                // OAuth sign-in
                OAuthSignInButtonGroup(
                    isEnabled: !viewModel.isAuthenticating,
                    appleAction: {
                        Task { await viewModel.signInWithApple() }
                    },
                    googleAction: {
                        Task { await viewModel.signInWithGoogle() }
                    },
                    githubAction: {
                        Task { await viewModel.signInWithGitHub() }
                    }
                )

                Spacer()
            }
        }
    }

    #if DEBUG
        #Preview {
            OnboardingLoginStep(viewModel: OnboardingViewModel(coordinator: MockOnboardingCoordinator(step: .login)))
                .frame(width: 440)
                .padding()
        }
    #endif

#endif
