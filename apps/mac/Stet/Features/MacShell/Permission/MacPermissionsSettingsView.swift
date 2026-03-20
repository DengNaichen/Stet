#if os(macOS)
import SwiftUI

struct MacRequiredPermissionsGateView: View {
    @StateObject private var viewModel: MacPermissionsViewModel

    init(appModel: any MacPermissionsCoordinating) {
        _viewModel = StateObject(wrappedValue: MacPermissionsViewModel(coordinator: appModel))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header
            stepContent
            footer
        }
        .padding(28)
        .frame(width: 760, height: 620, alignment: .topLeading)
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
            welcomeStep
        case .mode:
            modeStep
        case .apiKey:
            apiKeyStep
        case .login:
            loginStep
        case .permissions:
            permissionsStep
        case .shortcut:
            shortcutStep
        case .firstSuccess:
            firstSuccessStep
        case .done:
            doneStep
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

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    BulletRow(text: "Native Mac App")
                    BulletRow(text: "Preserve your natural expression")
                    BulletRow(text: "Privacy first: Login or bring your own API Key")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }

            Spacer()

            HStack {
                Spacer()

                Button("Continue") {
                    viewModel.continueOnboarding()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var modeStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            GroupBox("Privacy Note") {
                VStack(alignment: .leading, spacing: 10) {
                    BulletRow(text: "Your content will not be used for training")
                    BulletRow(text: "Cloud processing is transient and not stored")
                    BulletRow(text: "You can always use your own API Key")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }

            HStack(alignment: .top, spacing: 16) {
                onboardingChoiceCard(
                    title: "Use my own API Key",
                    details: [
                        "Full control",
                        "Use your own model provider",
                        "Billed directly to your account",
                    ],
                    buttonTitle: "Use API Key"
                ) {
                    viewModel.chooseOnboardingMode(.apiKey)
                }

                onboardingChoiceCard(
                    title: "Login to use",
                    details: [
                        "Faster setup",
                        "Managed experience",
                        "No manual Key configuration",
                    ],
                    buttonTitle: "Login to continue"
                ) {
                    viewModel.chooseOnboardingMode(.managed)
                }
            }

            Spacer()
        }
    }

    private var apiKeyStep: some View {
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

    private var loginStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Button("Continue with Google") {
                    viewModel.useUnavailableIdentityProvider("Google")
                }

                Button("Continue with Apple") {
                    viewModel.useUnavailableIdentityProvider("Apple")
                }
            }

            GroupBox("Continue with Email") {
                VStack(alignment: .leading, spacing: 14) {
                    if viewModel.isRelaySessionActive {
                        MessageBanner(
                            text: "Logged in as \(viewModel.relaySessionEmail ?? "current account").",
                            role: .success
                        )

                        HStack {
                            Spacer()

                            Button("Continue") {
                                viewModel.continueManagedFlow()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    } else {
                        TextField("name@example.com", text: $viewModel.email)
                            .textFieldStyle(.roundedBorder)

                        SecureField("Enter password", text: $viewModel.password)
                            .textFieldStyle(.roundedBorder)

                        if let authErrorMessage = viewModel.authErrorMessage {
                            MessageBanner(text: authErrorMessage, role: .error)
                        } else if let authStatusMessage = viewModel.authStatusMessage {
                            MessageBanner(text: authStatusMessage, role: .success)
                        }

                        HStack {
                            Spacer()

                            Button("Continue with Email") {
                                Task {
                                    await viewModel.signInWithEmail()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!viewModel.canSubmitEmailLogin)
                        }
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
            }
        }
    }

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    permissionGateRow(
                        title: "Microphone",
                        description: "Used to receive voice input",
                        statusText: viewModel.microphoneAccessStatusText,
                        tint: viewModel.microphoneAccessNeedsAttention ? .orange : .green
                    ) {
                        Button(viewModel.microphonePermissionActionTitle) {
                            viewModel.resolveMicrophoneAccess()
                        }
                    }

                    permissionGateRow(
                        title: "Accessibility / Input Control",
                        description: "Used to insert text into active apps",
                        statusText: viewModel.autoPasteStatusText,
                        tint: viewModel.autoPasteAccessNeedsAttention ? .orange : .green
                    ) {
                        HStack(spacing: 8) {
                            Button("Grant Permission") {
                                viewModel.requestAutoPasteAccess()
                            }

                            Button("Open System Settings") {
                                viewModel.openAccessibilitySettings()
                            }
                        }
                    }

                    if viewModel.microphoneAccessNeedsAttention || viewModel.autoPasteAccessNeedsAttention {
                        MessageBanner(
                            text: "Permissions not yet detected. Please authorize in System Settings and return.",
                            role: .warning
                        )
                    }
                }
                .padding(8)
            }

            Spacer()

            HStack {
                if viewModel.onboardingMode != nil {
                    Button("Back") {
                        viewModel.retreatOnboarding()
                    }
                }

                Spacer()

                Button("Continue") {
                    viewModel.continueOnboarding()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.hasRequiredPermissions)
            }
        }
    }

    private var shortcutStep: some View {
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

                    statusChecklistRow(
                        title: "Key press detected",
                        isComplete: viewModel.shortcutTestDetectedPress
                    )
                    statusChecklistRow(
                        title: "Released key loop completed",
                        isComplete: viewModel.shortcutTestCompletedRoundTrip
                    )
                    statusChecklistRow(
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

    private var firstSuccessStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            GroupBox("Example") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Example Input")
                        .font(.headline)

                    Text("Tomorrow afternoon, uh wait, 3 PM, help me book it")
                        .foregroundStyle(.secondary)

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
                    Button("Skip for now and try later") {
                        viewModel.continueOnboarding()
                    }
                }

                Button("Continue") {
                    viewModel.continueOnboarding()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canContinueFirstSuccessOnboarding && !viewModel.canSkipFirstSuccessOnboarding)
            }
        }
    }

    private var doneStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            GroupBox("Overview") {
                VStack(alignment: .leading, spacing: 12) {
                    summaryRow(title: "Shortcut", value: viewModel.shortcutSummaryText)
                    summaryRow(
                        title: "Current Mode",
                        value: viewModel.onboardingMode == .apiKey ? "API Key" : "Logged In"
                    )
                    summaryRow(
                        title: "Permissions",
                        value: viewModel.hasRequiredPermissions ? "Enabled" : "Check required"
                    )
                }
                .padding(8)
            }

            Spacer()

            HStack {
                Spacer()

                Button("Get Started") {
                    viewModel.finishOnboarding()
                }
                .buttonStyle(.borderedProminent)
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

    private func onboardingChoiceCard(
        title: String,
        details: [String],
        buttonTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.headline)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(details, id: \.self) { detail in
                    BulletRow(text: detail)
                }
            }

            Spacer(minLength: 0)

            Button(buttonTitle, action: action)
                .buttonStyle(.borderedProminent)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
    }

    private func summaryRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(.system(.body, design: .monospaced))
        }
    }

    private func statusChecklistRow(title: String, isComplete: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isComplete ? .green : .secondary)

            Text(title)
        }
    }

    @ViewBuilder
    private func permissionGateRow<Actions: View>(
        title: String,
        description: String,
        statusText: String,
        tint: Color,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)

                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                MacSettingsStatusBadge(text: statusText, tint: tint)
            }

            actions()
        }
    }
}
#endif
