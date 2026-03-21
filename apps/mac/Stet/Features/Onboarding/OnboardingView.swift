#if os(macOS)
import SwiftUI
import WebKit

struct OnboardingView: View {
    @StateObject private var viewModel: OnboardingViewModel

    init(appModel: any MacPermissionsCoordinating) {
        _viewModel = StateObject(wrappedValue: OnboardingViewModel(coordinator: appModel))
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left Panel (Native UI)
            VStack(alignment: .leading, spacing: 24) {
                header
                
                stepContent
                    .groupBoxStyle(CleanGroupBoxStyle())
                
                Spacer(minLength: 0)
                footer
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 40)
            .frame(width: 440, height: 640, alignment: .topLeading)
            .background(Color(nsColor: .windowBackgroundColor))
            
            // Right Panel (WebView)
            OnboardingWebView(step: viewModel.onboardingStep)
                .frame(width: 380, height: 640)
        }
        .frame(width: 820, height: 640)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(titleText)
                .font(.title2.weight(.semibold))

            Text(subtitleText)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Step \(viewModel.onboardingStep.progressIndex) of 7")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch viewModel.onboardingStep {
        case .welcome:
            OnboardingWelcomeStep(viewModel: viewModel)
        case .mode:
            OnboardingModeStep(viewModel: viewModel)
        case .apiKey:
            OnboardingAPIKeyStep(viewModel: viewModel)
        case .login:
            OnboardingLoginStep(viewModel: viewModel)
        case .permissions:
            OnboardingPermissionsStep(viewModel: viewModel)
        case .shortcut:
            OnboardingShortcutStep(viewModel: viewModel)
        case .firstSuccess:
            OnboardingFirstSuccessStep(viewModel: viewModel)
        case .done:
            OnboardingDoneStep(viewModel: viewModel)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button("Quit Stet") {
                NSApplication.shared.terminate(nil)
            }

            Spacer()
        }
    }

    private var titleText: String {
        switch viewModel.onboardingStep {
        case .welcome:
            return "As natural as native dictation, but smarter"
        case .mode:
            return "Choose how you start"
        case .apiKey:
            return "Enter and verify your API Key"
        case .login:
            return "Login to continue"
        case .permissions:
            return "One more step to get started"
        case .shortcut:
            return "Set your speaking shortcut"
        case .firstSuccess:
            return "Try saying something"
        case .done:
            return "You're all set"
        }
    }

    private var subtitleText: String {
        switch viewModel.onboardingStep {
        case .welcome:
            return "Preserve your original sentences, only apply necessary smart enhancements."
        case .mode:
            return "Choose your access method first. Permissions, shortcuts, and initial setup will follow automatically."
        case .apiKey:
            return "We only use this Key to make requests on your behalf. It will not be used for training."
        case .login:
            return "Login is only used to enable managed services and sync settings."
        case .permissions:
            return "Grant microphone and input control permissions so Stet can record and type text back into your apps."
        case .shortcut:
            return "We recommend a shortcut you can easily hold with one hand without accidental triggers."
        case .firstSuccess:
            return "Hold the shortcut and speak naturally. We'll preserve your intent while performing necessary cleanup."
        case .done:
            return "Hold your shortcut and start speaking anywhere you can type text."
        }
    }
}

#endif
