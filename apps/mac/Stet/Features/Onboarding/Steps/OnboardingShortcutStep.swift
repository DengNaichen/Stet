#if os(macOS)
import SwiftUI

struct OnboardingShortcutStep: View {
    @ObservedObject var viewModel: OnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            GroupBox("Set Shortcut") {
                VStack(alignment: .leading, spacing: 14) {
                    MacHotKeySettingsSectionView(hotkey: .dictation) { shortcut in
                        viewModel.updateShortcutSummary(shortcut)
                    }
                }
                .padding(8)
            }

            GroupBox("Test Area") {
                VStack(alignment: .leading, spacing: 12) {
                    Text(shortcutInstructionText)
                        .font(.headline)

                    if let previewText = viewModel.shortcutTestPreviewText {
                        MessageBanner(text: "Test Text: \(previewText)", role: .success)
                    }

                    StatusChecklistRow(
                        title: "Key press detected",
                        isComplete: viewModel.shortcutTestDetectedPress
                    )
                    StatusChecklistRow(
                        title: "Released key loop completed",
                        isComplete: viewModel.shortcutTestCompletedRoundTrip
                    )
                    StatusChecklistRow(
                        title: "First test result received",
                        isComplete: viewModel.shortcutTestPreviewText != nil
                    )
                }
                .padding(8)
            }

            Spacer()

            HStack {
                Button("Back") {
                    viewModel.retreatOnboarding()
                }

                Spacer()

                Button("Continue") {
                    viewModel.continueOnboarding()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canContinueShortcutOnboarding)
            }
        }
    }

    private var shortcutInstructionText: String {
        if !viewModel.shortcutTestDetectedPress {
            return "Hold the shortcut you configured and give it a try."
        }

        if !viewModel.shortcutTestCompletedRoundTrip {
            return "Shortcut detected. Keep holding and say something."
        }

        return "Shortcut configured. You can now hold it to start speaking."
    }
}

#if DEBUG
#Preview {
    OnboardingShortcutStep(viewModel: OnboardingViewModel(coordinator: MockOnboardingCoordinator(step: .shortcut)))
        .frame(width: 440)
        .padding()
}
#endif

#endif
