import SwiftUI

struct AuthView: View {
    @State private var viewModel = AuthViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var shouldDismissAfterAuthentication = false
    private let stats = DictationStatsModel.shared

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
        .task(id: viewModel.isSignedIn) {
            guard viewModel.isSignedIn else { return }
            await viewModel.fetchWallet()
        }
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

                MacSettingsValueRow(title: "Balance") {
                    if let credits = viewModel.balanceCredits {
                        Text("~\(formattedHourMin(creditsToSeconds(credits))) remaining")
                            .font(.system(.body))
                            .foregroundStyle(credits > 0 ? Color.primary : Color.red)
                    } else {
                        ProgressView()
                            .controlSize(.mini)
                    }
                }

                Divider()

                statsGrid

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

    private var statsGrid: some View {
        let duration = stats.allTimeTotalDuration()
        let words = stats.allTimeTotalWordCount()
        let durationMinutes = duration / 60
        let avgWPM = durationMinutes > 0 ? Int(Double(words) / durationMinutes) : 0
        let typingMinutes = Double(words) / 40.0
        let savedMinutes = max(0, typingMinutes - durationMinutes)

        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            StatCard(
                icon: "clock",
                value: formattedHourMin(duration),
                label: "Total dictation time"
            )
            StatCard(
                icon: "mic",
                value: formattedWordCount(words),
                label: "Words dictated"
            )
            StatCard(
                icon: "hourglass",
                value: formattedHourMin(savedMinutes * 60),
                label: "Time saved"
            )
            StatCard(
                icon: "bolt",
                value: "\(avgWPM) WPM",
                label: "Avg dictation speed"
            )
        }
    }

    private func formattedWordCount(_ count: Int) -> String {
        if count >= 1000 {
            let k = Double(count) / 1000.0
            return String(format: k.truncatingRemainder(dividingBy: 1) == 0 ? "%.0fK" : "%.1fK", k)
        }
        return "\(count)"
    }

    private func creditsToSeconds(_ credits: Int) -> TimeInterval {
        // Groq ASR at 2x markup: (0.04 USD/hr ÷ 3600) × 1_000_000 × 2.0 ≈ 22.22 credits/sec
        let creditsPerSecond = (0.04 / 3600.0) * 1_000_000 * 2.0
        return max(0, Double(credits) / creditsPerSecond)
    }

    private func formattedHourMin(_ seconds: TimeInterval) -> String {
        let totalMinutes = Int(seconds) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours == 0 {
            return "\(minutes) min"
        }
        if minutes == 0 {
            return "\(hours) hr"
        }
        return "\(hours) hr \(minutes) min"
    }

    private struct StatCard: View {
        let icon: String
        let value: String
        let label: String

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)

                Text(value)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
        }
    }

    private var signedOutCard: some View {
        MacSettingsCard(
            title: "Continue with Apple, Google, or GitHub"
        ) {
            VStack(alignment: .leading, spacing: 16) {
                OAuthSignInButtonGroup(
                    isEnabled: !viewModel.isLoading,
                    appleAction: {
                        shouldDismissAfterAuthentication = true
                        Task {
                            await viewModel.signInWithApple()
                        }
                    },
                    googleAction: {
                        shouldDismissAfterAuthentication = true
                        Task {
                            await viewModel.signInWithGoogle()
                        }
                    },
                    githubAction: {
                        shouldDismissAfterAuthentication = true
                        Task {
                            await viewModel.signInWithGitHub()
                        }
                    }
                )

                if viewModel.isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                            .controlSize(.small)
                        Spacer()
                    }
                }

                feedbackView
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
