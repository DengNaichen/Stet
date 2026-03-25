import SwiftUI

struct AuthView: View {
    @State private var viewModel = AuthViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var shouldDismissAfterAuthentication = false

    var body: some View {
        VStack(spacing: 20) {
            if viewModel.isSignedIn {
                signedInCard
            } else {
                signedOutCard
            }
        }
        .padding(24)
        .frame(maxWidth: 460)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .topLeading) {
            dismissButton
                .padding(.top, 12)
                .padding(.leading, 12)
        }
        .onChange(of: viewModel.isSignedIn) { _, isSignedIn in
            guard isSignedIn else { return }
            viewModel.clearFeedback()
            if shouldDismissAfterAuthentication {
                shouldDismissAfterAuthentication = false
                dismiss()
            }
        }
    }

    private var dismissButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.95))
                )
                .overlay(
                    Circle()
                        .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.cancelAction)
        .help("Close")
    }

    private var signedInCard: some View {
        MacSettingsCard(
            title: "You're signed in"
        ) {
            VStack(alignment: .leading, spacing: 14) {
                MacSettingsValueRow(title: "Email") {
                    Text(viewModel.accountEmailText)
                        .font(.system(.body, design: .monospaced))
                }

                MacSettingsValueRow(title: "Status") {
                    MacSettingsStatusBadge(text: "Active", tint: .green)
                }

                feedbackView

                HStack {
                    Button("Done") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)

                    Spacer()

                    Button("Sign Out", role: .destructive) {
                        Task {
                            await viewModel.signOut()
                        }
                    }
                    .disabled(viewModel.isLoading)
                }
            }
        }
    }

    private var signedOutCard: some View {
        MacSettingsCard(
            title: "Continue with Apple, Google, or GitHub"
        ) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(spacing: 10) {
                    AppleSignInButton {
                        shouldDismissAfterAuthentication = true
                        Task {
                            await viewModel.signInWithApple()
                        }
                    }

                    GoogleSignInButton {
                        shouldDismissAfterAuthentication = true
                        Task {
                            await viewModel.signInWithGoogle()
                        }
                    }

                    GitHubSignInButton {
                        shouldDismissAfterAuthentication = true
                        Task {
                            await viewModel.signInWithGitHub()
                        }
                    }
                }
                .disabled(viewModel.isLoading)

                if viewModel.isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                            .controlSize(.small)
                        Spacer()
                    }
                }

                OnboardingInputField(
                    label: "Email",
                    placeholder: "name@example.com",
                    text: $viewModel.email,
                    mode: .text
                )
                .disableAutocorrection(true)

                OnboardingInputField(
                    label: "Password",
                    placeholder: "Enter your password",
                    text: $viewModel.password,
                    mode: .secure
                )

                if viewModel.showsConfirmPasswordField {
                    OnboardingInputField(
                        label: "Confirm Password",
                        placeholder: "Confirm password",
                        text: $viewModel.confirmPassword,
                        mode: .secure
                    )
                }

                feedbackView

                HStack(spacing: 12) {
                    Button(viewModel.modeToggleTitle) {
                        viewModel.toggleAuthMode()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                    Spacer()

                    Button(viewModel.primaryActionTitle) {
                        shouldDismissAfterAuthentication = true
                        Task {
                            if viewModel.showsConfirmPasswordField {
                                await viewModel.signUp()
                            } else {
                                await viewModel.signIn()
                            }
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!viewModel.canSubmit)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .onSubmit {
            guard viewModel.canSubmit else { return }
            shouldDismissAfterAuthentication = true
            Task {
                await viewModel.signIn()
            }
        }
    }

    @ViewBuilder
    private var feedbackView: some View {
        if let error = viewModel.errorMessage {
            MessageBanner(text: error, role: .error)
        } else if let status = viewModel.statusMessage {
            MessageBanner(text: status, role: .info)
        }
    }

    // MARK: - Local UI components (scoped to AuthView)

    private enum MessageBannerRole {
        case info, success, warning, error

        var tint: Color {
            switch self {
            case .info: return .secondary
            case .success: return .green
            case .warning: return .orange
            case .error: return .red
            }
        }
    }

    private struct MessageBanner: View {
        let text: String
        let role: MessageBannerRole
        var strokeOpacity: Double = 0.16
        var fillOpacity: Double = 0.08
        var icon: String? = nil

        var body: some View {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(role.tint)
                }
                Text(text)
                    .font(.footnote)
                    .foregroundStyle(role.tint)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(role.tint.opacity(fillOpacity))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(role.tint.opacity(strokeOpacity), lineWidth: 1)
            )
        }
    }

}

#Preview("Signed Out State") {
    AuthView()
        .frame(width: 520, height: 580)
}
