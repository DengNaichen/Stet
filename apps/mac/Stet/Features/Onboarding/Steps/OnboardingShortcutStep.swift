#if os(macOS)
    import SwiftUI

    struct OnboardingShortcutStep: View {
        @ObservedObject var viewModel: OnboardingViewModel

        var body: some View {
            VStack(alignment: .leading, spacing: 18) {
                MacHotKeySettingsSectionView(hotkey: .dictation) { shortcut in
                    viewModel.updateShortcutSummary(shortcut)
                }

                Text("We've set Command + . as your default shortcut. Try pressing it now to see it in action.")
                    .font(.body)
                    .foregroundStyle(.secondary)

                Spacer()

                HStack {
                    OnboardingBackButton { viewModel.retreatOnboarding() }

                    Spacer()

                    OnboardingActionButton(
                        title: "Continue",
                        isEnabled: true,
                        minHeight: 48
                    ) {
                        viewModel.continueOnboarding()
                    }
                }
            }
        }
    }

    #if DEBUG
        #Preview {
            OnboardingShortcutStep(
                viewModel: OnboardingViewModel(coordinator: MockOnboardingCoordinator(step: .shortcut))
            )
            .frame(width: 440)
            .padding()
        }
    #endif

#endif
