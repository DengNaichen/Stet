#if os(macOS)
import AppKit
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
            return "像系统听写一样自然，但更聪明"
        case .mode:
            return "选择你的开始方式"
        case .apiKey:
            return "输入并验证你的 API Key"
        case .login:
            return "登录继续"
        case .permissions:
            return "还差一步就能开始"
        case .shortcut:
            return "设置你的说话快捷键"
        case .firstSuccess:
            return "试着说一句话"
        case .done:
            return "可以开始了"
        }
    }

    private var subtitleText: String {
        switch viewModel.onboardingStep {
        case .welcome:
            return "保留你的原句，只做必要的智能增强。"
        case .mode:
            return "先选接入方式，后面的权限、快捷键和首次成功识别会自动接上。"
        case .apiKey:
            return "我们只用这个 Key 代表你发起请求，不会用于训练。"
        case .login:
            return "登录仅用于启用托管服务与同步设置。"
        case .permissions:
            return "把麦克风和输入控制权限打开后，Stet 才能录音并把文字写回当前应用。"
        case .shortcut:
            return "建议选一个你能单手按住、不容易误触的快捷键。"
        case .firstSuccess:
            return "按住快捷键，说一句自然的话。我们会尽量保留你的原意，只做必要整理。"
        case .done:
            return "在任何可输入文字的地方，按住快捷键开始说话。"
        }
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    bulletRow("Mac 原生应用")
                    bulletRow("尽量保留你的表达")
                    bulletRow("隐私优先，可登录也可自带 API Key")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }

            Spacer()

            HStack {
                Spacer()

                Button("继续") {
                    viewModel.continueOnboarding()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var modeStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            GroupBox("隐私说明") {
                VStack(alignment: .leading, spacing: 10) {
                    bulletRow("你的内容不会用于训练")
                    bulletRow("如使用云处理，处理后不留存")
                    bulletRow("你也可以使用自己的 API Key")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }

            HStack(alignment: .top, spacing: 16) {
                onboardingChoiceCard(
                    title: "使用自己的 API Key",
                    details: [
                        "更高控制权",
                        "使用你自己的模型提供商",
                        "费用由你自己的账户结算",
                    ],
                    buttonTitle: "使用 API Key"
                ) {
                    viewModel.chooseOnboardingMode(.apiKey)
                }

                onboardingChoiceCard(
                    title: "登录使用",
                    details: [
                        "设置更快",
                        "托管体验",
                        "不需要手动配置 Key",
                    ],
                    buttonTitle: "登录继续"
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

                    SecureField("输入 API Key", text: $viewModel.apiKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))

                    if let apiKeyStatusMessage = viewModel.apiKeyStatusMessage {
                        messageRow(text: apiKeyStatusMessage, tint: .green)
                    } else if let apiKeyErrorMessage = viewModel.apiKeyErrorMessage {
                        messageRow(text: apiKeyErrorMessage, tint: .red)
                    }
                }
                .padding(8)
            }

            Spacer()

            HStack {
                Button("返回") {
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
                        messageRow(
                            text: "已登录为 \(viewModel.relaySessionEmail ?? "当前账号")。",
                            tint: .green
                        )

                        HStack {
                            Spacer()

                            Button("继续") {
                                viewModel.continueManagedFlow()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    } else {
                        TextField("name@example.com", text: $viewModel.email)
                            .textFieldStyle(.roundedBorder)

                        SecureField("输入密码", text: $viewModel.password)
                            .textFieldStyle(.roundedBorder)

                        if let authErrorMessage = viewModel.authErrorMessage {
                            messageRow(text: authErrorMessage, tint: .red)
                        } else if let authStatusMessage = viewModel.authStatusMessage {
                            messageRow(text: authStatusMessage, tint: .green)
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
                Button("返回") {
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
                        title: "麦克风",
                        description: "用于接收语音输入",
                        statusText: viewModel.microphoneAccessStatusText,
                        tint: viewModel.microphoneAccessNeedsAttention ? .orange : .green
                    ) {
                        Button(viewModel.microphonePermissionActionTitle) {
                            viewModel.resolveMicrophoneAccess()
                        }
                    }

                    permissionGateRow(
                        title: "Accessibility / 输入控制",
                        description: "用于把文本插入当前应用",
                        statusText: viewModel.autoPasteStatusText,
                        tint: viewModel.autoPasteAccessNeedsAttention ? .orange : .green
                    ) {
                        HStack(spacing: 8) {
                            Button("开启权限") {
                                viewModel.requestAutoPasteAccess()
                            }

                            Button("打开系统设置") {
                                viewModel.openAccessibilitySettings()
                            }
                        }
                    }

                    if viewModel.microphoneAccessNeedsAttention || viewModel.autoPasteAccessNeedsAttention {
                        messageRow(
                            text: "还没有检测到权限开启。请在系统设置中完成授权后返回。",
                            tint: .orange
                        )
                    }
                }
                .padding(8)
            }

            Spacer()

            HStack {
                if viewModel.onboardingMode != nil {
                    Button("返回") {
                        viewModel.retreatOnboarding()
                    }
                }

                Spacer()

                Button("继续") {
                    viewModel.continueOnboarding()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.hasRequiredPermissions)
            }
        }
    }

    private var shortcutStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            GroupBox("设置快捷键") {
                VStack(alignment: .leading, spacing: 14) {
                    MacHotKeySettingsSectionView(hotkey: .dictation) { shortcut in
                        viewModel.updateShortcutSummary(shortcut)
                    }
                }
                .padding(8)
            }

            GroupBox("测试区") {
                VStack(alignment: .leading, spacing: 12) {
                    Text(shortcutInstructionText)
                        .font(.headline)

                    if let previewText = viewModel.shortcutTestPreviewText {
                        messageRow(text: "测试文本：\(previewText)", tint: .green)
                    }

                    statusChecklistRow(
                        title: "已检测到按下",
                        isComplete: viewModel.shortcutTestDetectedPress
                    )
                    statusChecklistRow(
                        title: "已完成按下到松开闭环",
                        isComplete: viewModel.shortcutTestCompletedRoundTrip
                    )
                    statusChecklistRow(
                        title: "已拿到一次测试结果",
                        isComplete: viewModel.shortcutTestPreviewText != nil
                    )
                }
                .padding(8)
            }

            Spacer()

            HStack {
                Button("返回") {
                    viewModel.retreatOnboarding()
                }

                Spacer()

                Button("继续") {
                    viewModel.continueOnboarding()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canContinueShortcutOnboarding)
            }
        }
    }

    private var firstSuccessStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            GroupBox("示例") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("示例输入")
                        .font(.headline)

                    Text("明天下午，呃不对，三点帮我约一下")
                        .foregroundStyle(.secondary)

                    if let firstSuccessPreviewText = viewModel.firstSuccessPreviewText {
                        messageRow(text: "成功了：\(firstSuccessPreviewText)", tint: .green)
                    } else if let firstSuccessFailureMessage = viewModel.firstSuccessFailureMessage {
                        messageRow(text: firstSuccessFailureMessage, tint: .red)
                    }
                }
                .padding(8)
            }

            Spacer()

            HStack {
                Button("返回") {
                    viewModel.retreatOnboarding()
                }

                Spacer()

                if viewModel.canSkipFirstSuccessOnboarding && !viewModel.canContinueFirstSuccessOnboarding {
                    Button("先进入应用，稍后再试") {
                        viewModel.continueOnboarding()
                    }
                }

                Button("继续") {
                    viewModel.continueOnboarding()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canContinueFirstSuccessOnboarding && !viewModel.canSkipFirstSuccessOnboarding)
            }
        }
    }

    private var doneStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            GroupBox("提醒") {
                VStack(alignment: .leading, spacing: 12) {
                    summaryRow(title: "快捷键", value: viewModel.shortcutSummaryText)
                    summaryRow(
                        title: "当前模式",
                        value: viewModel.onboardingMode == .apiKey ? "API Key" : "已登录"
                    )
                    summaryRow(
                        title: "权限",
                        value: viewModel.hasRequiredPermissions ? "已开启" : "仍需检查"
                    )
                }
                .padding(8)
            }

            Spacer()

            HStack {
                Spacer()

                Button("开始使用") {
                    viewModel.finishOnboarding()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var shortcutInstructionText: String {
        if !viewModel.shortcutTestDetectedPress {
            return "按住你设置的快捷键试试看。"
        }

        if !viewModel.shortcutTestCompletedRoundTrip {
            return "已检测到快捷键，保持按住并说一句话。"
        }

        return "快捷键设置成功；现在你可以按住它开始说话了。"
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
                    bulletRow(detail)
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

    private func bulletRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 6, height: 6)
                .padding(.top, 6)

            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
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
                    .strokeBorder(tint.opacity(0.18), lineWidth: 1)
            )
    }
}
#endif
