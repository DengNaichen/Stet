import SwiftUI

struct AuthView: View {
    private enum Field: Hashable {
        case email
        case password
    }

    @State private var viewModel = AuthViewModel()
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?
    @State private var shouldDismissAfterAuthentication = false

    var body: some View {
        VStack(spacing: 20) {
            headerCard

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
        .onChange(of: viewModel.isSignedIn) { _, isSignedIn in
            guard isSignedIn else { return }
            viewModel.clearFeedback()
            if shouldDismissAfterAuthentication {
                shouldDismissAfterAuthentication = false
                dismiss()
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
            title: "Continue with Email"
        ) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    MacSettingsStatusBadge(
                        text: viewModel.configurationStatusText,
                        tint: viewModel.configurationStatusTint ? .green : .orange
                    )

                    Spacer()

                    if viewModel.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                LabeledTextField<Field>(
                    title: "Email",
                    placeholder: "name@example.com",
                    text: $viewModel.email,
                    focused: $focusedField,
                    focusEquals: .email
                )
                .disableAutocorrection(true)

                LabeledSecureField<Field>(
                    title: "Password",
                    placeholder: "Enter your password",
                    text: $viewModel.password,
                    focused: $focusedField,
                    focusEquals: .password
                )

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
            case .info:    return .secondary
            case .success: return .green
            case .warning: return .orange
            case .error:   return .red
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

    private struct LabeledField<Content: View>: View {
        let title: String
        @ViewBuilder var content: () -> Content

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                content()
            }
        }
    }

    private struct LabeledTextField<F: Hashable>: View {
        let title: String
        let placeholder: String
        @Binding var text: String
        var focused: FocusState<F?>.Binding?
        var focusEquals: F?

        var body: some View {
            LabeledField(title: title) {
                if let focused, let focusEquals {
                    TextField(placeholder, text: $text)
                        .textFieldStyle(.roundedBorder)
                        .focused(focused, equals: focusEquals)
                } else {
                    TextField(placeholder, text: $text)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
    }

    private struct LabeledSecureField<F: Hashable>: View {
        let title: String
        let placeholder: String
        @Binding var text: String
        var focused: FocusState<F?>.Binding?
        var focusEquals: F?

        var body: some View {
            LabeledField(title: title) {
                if let focused, let focusEquals {
                    SecureField(placeholder, text: $text)
                        .textFieldStyle(.roundedBorder)
                        .focused(focused, equals: focusEquals)
                } else {
                    SecureField(placeholder, text: $text)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
    }
}

#Preview("Signed Out State") {
    AuthView()
        .frame(width: 520, height: 480)
}
