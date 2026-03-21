#if os(macOS)
import SwiftUI

struct OnboardingAPIKeyStep: View {
    @ObservedObject var viewModel: OnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("Provider", selection: $viewModel.apiKeyProvider) {
                        ForEach(DictationProvider.allCases) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 220)

                    SecureField("Enter API Key", text: $viewModel.apiKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))

                    if let apiKeyStatusMessage = viewModel.apiKeyStatusMessage {
                        MessageBanner(text: apiKeyStatusMessage, role: .success)
                    } else if let apiKeyErrorMessage = viewModel.apiKeyErrorMessage {
                        MessageBanner(text: apiKeyErrorMessage, role: .error)
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

                Button(viewModel.apiKeyPrimaryButtonTitle) {
                    Task {
                        await viewModel.completeAPIKeyFlow()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isValidatingAPIKey)
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
