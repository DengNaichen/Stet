#if os(macOS)
import SwiftUI

struct OnboardingFirstSuccessStep: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @State private var draftText = ""
    @FocusState private var isDraftFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            GroupBox("Say something") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Click into the box, then use your hotkey. The transcript should land here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(nsColor: .textBackgroundColor).opacity(0.72))

                        TextEditor(text: $draftText)
                            .focused($isDraftFocused)
                            .font(.body)
                            .scrollContentBackground(.hidden)
                            .padding(8)

                        if draftText.isEmpty {
                            Text("Say something out loud...")
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 16)
                                .allowsHitTesting(false)
                        }
                    }
                    .frame(minHeight: 140)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                    )

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
                    isEnabled: viewModel.canContinueFirstSuccessOnboarding || viewModel.canSkipFirstSuccessOnboarding,
                    minHeight: 48
                ) {
                    viewModel.continueOnboarding()
                }
            }
        }
        .onAppear {
            isDraftFocused = true
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
