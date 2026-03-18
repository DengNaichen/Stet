import SwiftUI
internal import Auth

struct AuthView: View {
    private enum Field: Hashable {
        case email
        case password
    }

    @State private var viewModel = AuthViewModel()
    private let supabase = SupabaseService.shared
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?
    @State private var shouldDismissAfterAuthentication = false

    var body: some View {
        VStack(spacing: 20) {
            headerCard

            if let session = supabase.currentSession {
                signedInCard(session: session)
            } else {
                signedOutCard
            }
        }
        .padding(24)
        .frame(maxWidth: 460)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: supabase.currentSession == nil) { _, isSignedOut in
            if !isSignedOut {
                viewModel.clearFeedback()
                if shouldDismissAfterAuthentication {
                    shouldDismissAfterAuthentication = false
                    dismiss()
                }
            }
        }
    }

    private var headerCard: some View {
        HStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.accentColor.opacity(0.95), Color.accentColor.opacity(0.65)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 56, height: 56)
                .overlay {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 6) {
                Text("Stet Account")
                    .font(.title3.weight(.semibold))

                Text("Use your Supabase account to sign in on this Mac and access cloud-backed features.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
    }

    private func signedInCard(session: Session) -> some View {
        MacSettingsCard(
            title: "You're signed in",
            description: "This Mac is currently connected to your Stet account."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                MacSettingsValueRow(title: "Email") {
                    Text(session.user.email ?? "Unknown user")
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
            title: "Continue with Email",
            description: "Enter the email and password for your Supabase account."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    MacSettingsStatusBadge(
                        text: supabase.isConfigured ? "Supabase Ready" : "Setup Required",
                        tint: supabase.isConfigured ? .green : .orange
                    )

                    Spacer()

                    if viewModel.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Email")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)

                    TextField("name@example.com", text: $viewModel.email)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .email)
                        .disableAutocorrection(true)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Password")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)

                    SecureField("Enter your password", text: $viewModel.password)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .password)
                }

                feedbackView

                HStack(spacing: 12) {
                    Button("Close") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)

                    Button("Create Account") {
                        shouldDismissAfterAuthentication = true
                        Task {
                            await viewModel.signUp()
                        }
                    }
                    .disabled(!viewModel.canSubmit)

                    Spacer()

                    Button("Sign In") {
                        shouldDismissAfterAuthentication = true
                        Task {
                            await viewModel.signIn()
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!viewModel.canSubmit)
                }

                Text("New accounts may require email confirmation before the first sign-in.")
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
        .task {
            if focusedField == nil {
                focusedField = .email
            }
        }
    }

    @ViewBuilder
    private var feedbackView: some View {
        if let error = viewModel.errorMessage {
            messageRow(text: error, tint: .red)
        } else if let status = viewModel.statusMessage {
            messageRow(text: status, tint: .secondary)
        }
    }

    private func messageRow(text: String, tint: Color) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(tint.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(tint.opacity(0.16), lineWidth: 1)
            )
    }
}


#Preview("Signed Out State") {
    AuthView()
        .frame(width: 520, height: 480)
}
