#if os(macOS)
    import SwiftUI

    struct OnboardingLoginStep: View {
        @ObservedObject var viewModel: OnboardingViewModel

        var body: some View {
            VStack(alignment: .center, spacing: 18) {
                // OAuth sign-in
                VStack(spacing: 10) {
                    AppleSignInButton {
                        Task { await viewModel.signInWithApple() }
                    }
                    .frame(width: 316)

                    GoogleSignInButton {
                        Task { await viewModel.signInWithGoogle() }
                    }
                    .frame(width: 316)

                    GitHubSignInButton {
                        Task { await viewModel.signInWithGitHub() }
                    }
                    .frame(width: 316)
                }
                .disabled(viewModel.isAuthenticating)

                // Divider
                HStack(spacing: 10) {
                    Rectangle().fill(Color.primary.opacity(0.09)).frame(height: 1)
                    Text("or email").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    Rectangle().fill(Color.primary.opacity(0.09)).frame(height: 1)
                }

                // Email section
                if viewModel.isRelaySessionActive {
                    MessageBanner(
                        text: "Logged in as \(viewModel.relaySessionEmail ?? "current account").",
                        role: .success
                    )
                    .fixedSize(horizontal: true, vertical: false)

                    OnboardingActionButton(title: "Continue", minHeight: 48) {
                        viewModel.continueManagedFlow()
                    }
                    .frame(width: 316)
                } else {
                    VStack(spacing: 14) {
                        OnboardingInputField(
                            label: "Email",
                            placeholder: "name@example.com",
                            text: $viewModel.email,
                            mode: .text
                        )
                        .frame(width: 316)

                        OnboardingInputField(
                            label: "Password",
                            placeholder: "Enter password",
                            text: $viewModel.password,
                            mode: .secure
                        )
                        .frame(width: 316)

                        if viewModel.showsConfirmPasswordField {
                            OnboardingInputField(
                                label: "Confirm Password",
                                placeholder: "Confirm password",
                                text: $viewModel.confirmPassword,
                                mode: .secure
                            )
                            .frame(width: 316)
                        }

                        if let msg = viewModel.authErrorMessage {
                            MessageBanner(text: msg, role: .error)
                                .fixedSize(horizontal: true, vertical: false)
                        } else if let msg = viewModel.authStatusMessage {
                            MessageBanner(text: msg, role: .success)
                                .fixedSize(horizontal: true, vertical: false)
                        }

                        HStack(spacing: 10) {
                            Button(viewModel.emailModeToggleTitle) {
                                viewModel.toggleEmailAuthMode()
                            }
                            .buttonStyle(.plain)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                            OnboardingActionButton(
                                title: viewModel.emailPrimaryActionTitle,
                                isEnabled: viewModel.canSubmitEmailLogin,
                                minHeight: 48
                            ) {
                                Task {
                                    if viewModel.showsConfirmPasswordField {
                                        await viewModel.signUpWithEmail()
                                    } else {
                                        await viewModel.signInWithEmail()
                                    }
                                }
                            }
                        }
                        .frame(width: 316)
                    }
                }

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
