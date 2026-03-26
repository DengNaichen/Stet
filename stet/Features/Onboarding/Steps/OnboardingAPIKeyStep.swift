#if os(macOS)
    import SwiftUI

    struct OnboardingAPIKeyStep: View {
        @ObservedObject var viewModel: OnboardingViewModel

        var body: some View {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Provider")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    OnboardingProviderPicker(
                        items: Array(DictationProvider.allCases),
                        displayName: { $0.displayName },
                        selection: $viewModel.apiKeyProvider
                    )
                }

                OnboardingInputField(
                    label: "API Key",
                    placeholder: viewModel.apiKeyProvider.apiKeyPlaceholder,
                    text: $viewModel.apiKey,
                    mode: .secure,
                    isMonospaced: true
                )
                .fixedSize(horizontal: false, vertical: true)

                if let msg = viewModel.apiKeyStatusMessage {
                    MessageBanner(text: msg, role: .success)
                        .fixedSize(horizontal: true, vertical: false)
                } else if let msg = viewModel.apiKeyErrorMessage {
                    MessageBanner(text: msg, role: .error)
                        .fixedSize(horizontal: true, vertical: false)
                }

                Spacer()

                OnboardingActionButton(
                    title: viewModel.apiKeyPrimaryButtonTitle,
                    isEnabled: !viewModel.isValidatingAPIKey,
                    minHeight: 48
                ) {
                    Task {
                        await viewModel.completeAPIKeyFlow()
                    }
                }
            }
        }
    }

    #if DEBUG
        #Preview {
            OnboardingAPIKeyStep(viewModel: OnboardingViewModel(coordinator: MockOnboardingCoordinator(step: .apiKey)))
                .frame(width: 440)
                .padding()
        }
    #endif

#endif
