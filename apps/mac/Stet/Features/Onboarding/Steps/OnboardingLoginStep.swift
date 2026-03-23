#if os(macOS)
import SwiftUI

struct OnboardingLoginStep: View {
    @ObservedObject var viewModel: OnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(spacing: 12) {
                OnboardingBrandActionButton(
                    title: "Continue with Google",
                    background: Color.black.opacity(0.94),
                    foreground: Color(red: 0.92, green: 0.92, blue: 0.92),
                    strokeColor: Color.white.opacity(0.18)
                ) {
                    GoogleBrandMark()
                } action: {
                    Task {
                        await viewModel.signInWithGoogle()
                    }
                }

                OnboardingBrandActionButton(
                    title: "Continue with GitHub",
                    background: Color(red: 0.14, green: 0.16, blue: 0.18),
                    foreground: .white
                ) {
                    GitHubBrandMark()
                } action: {
                    Task {
                        await viewModel.signInWithGitHub()
                    }
                }
            }
            .disabled(viewModel.isAuthenticating)

            GroupBox("Continue with Email") {
                VStack(alignment: .leading, spacing: 14) {
                    if viewModel.isRelaySessionActive {
                        MessageBanner(
                            text: "Logged in as \(viewModel.relaySessionEmail ?? "current account").",
                            role: .success
                        )

                        HStack {
                            Spacer()

                            OnboardingActionButton(
                                title: "Continue",
                                minHeight: 48
                            ) {
                                viewModel.continueManagedFlow()
                            }
                        }
                    } else {
                        TextField("name@example.com", text: $viewModel.email)
                            .textFieldStyle(.roundedBorder)

                        SecureField("Enter password", text: $viewModel.password)
                            .textFieldStyle(.roundedBorder)

                        if let authErrorMessage = viewModel.authErrorMessage {
                            MessageBanner(text: authErrorMessage, role: .error)
                        } else if let authStatusMessage = viewModel.authStatusMessage {
                            MessageBanner(text: authStatusMessage, role: .success)
                        }

                        HStack {
                            Spacer()

                            OnboardingActionButton(
                                title: "Continue with Email",
                                isEnabled: viewModel.canSubmitEmailLogin,
                                minHeight: 48
                            ) {
                                Task {
                                    await viewModel.signInWithEmail()
                                }
                            }
                        }
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
            }
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
