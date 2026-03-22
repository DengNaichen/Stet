#if os(macOS)
import SwiftUI

struct OnboardingLoginStep: View {
    @ObservedObject var viewModel: OnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Button("Continue with Google") {
                    Task {
                        await viewModel.signInWithGoogle()
                    }
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isAuthenticating)

                Button("Continue with GitHub") {
                    Task {
                        await viewModel.signInWithGitHub()
                    }
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isAuthenticating)
            }

            GroupBox("Continue with Email") {
                VStack(alignment: .leading, spacing: 14) {
                    if viewModel.isRelaySessionActive {
                        MessageBanner(
                            text: "Logged in as \(viewModel.relaySessionEmail ?? "current account").",
                            role: .success
                        )

                        HStack {
                            Spacer()

                            Button("Continue") {
                                viewModel.continueManagedFlow()
                            }
                            .buttonStyle(.borderedProminent)
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

                            Button("Continue with Email") {
                                Task {
                                    await viewModel.signInWithEmail()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!viewModel.canSubmitEmailLogin)
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
