#if os(macOS)
    import SwiftUI
    import StetCore

    struct OnboardingVisualPanel: View {
        let step: MacOnboardingStep
        @ObservedObject var viewModel: OnboardingViewModel
        @ObservedObject var appearanceViewModel: MacAppearanceSettingsViewModel
        let onAppearanceThemeChange: ((MacDictationVisualTheme) -> Void)?
        let onAppearanceThemeApply: ((MacDictationVisualTheme) -> Void)?
        @StateObject private var microphoneTestViewModel = MicrophoneTestViewModel(
            microphoneTestService: DefaultMicrophoneTestService.shared
        )
        @State private var firstSuccessDraftText = ""
        @FocusState private var isFirstSuccessDraftFocused: Bool

        init(
            step: MacOnboardingStep,
            viewModel: OnboardingViewModel,
            appearanceViewModel: MacAppearanceSettingsViewModel,
            onAppearanceThemeChange: ((MacDictationVisualTheme) -> Void)? = nil,
            onAppearanceThemeApply: ((MacDictationVisualTheme) -> Void)? = nil
        ) {
            self.step = step
            self.viewModel = viewModel
            self.appearanceViewModel = appearanceViewModel
            self.onAppearanceThemeChange = onAppearanceThemeChange
            self.onAppearanceThemeApply = onAppearanceThemeApply
        }

        var body: some View {
            ZStack {
                if step == .appearance {
                    backgroundGradient
                }

                if step == .language {
                    engineDownloadProgressPanel
                } else if step == .shortcut {
                    OnboardingKeyboardView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(32)
                } else if step == .permissions {
                    VStack(spacing: 24) {
                        Spacer()

                        OnboardingMicrophoneLevelMeter(level: microphoneTestViewModel.audioLevel)
                            .frame(height: 40)
                            .padding(.horizontal, 0)

                        OnboardingActionButton(
                            title: microphoneTestViewModel.isRecording ? "Stop Recording" : "Start Recording",
                            systemImage: microphoneTestViewModel.isRecording ? "stop.circle.fill" : "record.circle",
                            background: microphoneTestViewModel.isRecording
                                ? Color.red.opacity(0.15) : Color.white.opacity(0.08),
                            foreground: microphoneTestViewModel.isRecording ? .red : .primary,
                            strokeColor: microphoneTestViewModel.isRecording
                                ? Color.red.opacity(0.50) : Color.primary.opacity(0.25),
                            minHeight: 48,
                            isCentered: true
                        ) {
                            Task {
                                if microphoneTestViewModel.isRecording {
                                    await microphoneTestViewModel.stopRecording()
                                } else {
                                    await microphoneTestViewModel.startRecording()
                                }
                            }
                        }

                        Spacer()
                    }
                    .padding(32)
                    .onDisappear {
                        Task { await microphoneTestViewModel.stopRecording() }
                    }
                } else if step == .firstSuccess {
                    VStack(spacing: 24) {
                        Spacer()

                        VStack(spacing: 8) {
                            Text("Try saying:")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text("I am now using this app to dictate this sentence")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(.primary)
                        }

                        ZStack(alignment: .topLeading) {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color(nsColor: .textBackgroundColor).opacity(0.72))

                            TextField("", text: $firstSuccessDraftText, axis: .vertical)
                                .textFieldStyle(.plain)
                                .font(.body)
                                .foregroundStyle(.primary)
                                .focused($isFirstSuccessDraftFocused)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 16)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        }
                        .frame(height: 120)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                        )

                        OnboardingHotkeyDisplay()

                        Spacer()
                    }
                    .padding(32)
                    .onAppear {
                        if firstSuccessDraftText.isEmpty {
                            firstSuccessDraftText = viewModel.firstSuccessPreviewText ?? ""
                        }
                        isFirstSuccessDraftFocused = true
                    }
                } else if step == .appearance {
                    VStack(spacing: 14) {
                        OnboardingAppearanceCoverFlowPanel(
                            selectedTheme: appearanceViewModel.shaderTheme,
                            isSelectedThemeApplied: appearanceViewModel.hasAppliedSelectedTheme,
                            onFocusedThemeChange: { theme in
                                onAppearanceThemeChange?(theme)
                            },
                            onApplyTheme: { theme in
                                onAppearanceThemeApply?(theme)
                            }
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .padding(18)
                } else if step == .done {
                    VStack {
                        Spacer()
                        Spacer()
                    }
                    .padding(32)
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .center, spacing: 12) {
                            OnboardingPill(
                                text: "Live preview", systemImage: "sparkles", tint: presentation.accentColor)

                            Spacer(minLength: 0)

                            Image(systemName: presentation.systemImage)
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(presentation.accentColor)
                                .padding(10)
                                .background(
                                    Circle()
                                        .fill(presentation.accentColor.opacity(0.12))
                                )
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text(presentation.panelTitle)
                                .font(.system(size: 24, weight: .semibold, design: .rounded))

                            Text(presentation.panelSubtitle)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        OnboardingStageArtifact(
                            title: presentation.heroTitle,
                            subtitle: presentation.heroSubtitle,
                            systemImage: presentation.systemImage,
                            tint: presentation.accentColor
                        )

                        VStack(spacing: 10) {
                            ForEach(presentation.metrics) { metric in
                                OnboardingGlassCard(
                                    cornerRadius: 18, fillOpacity: 0.08, strokeOpacity: 0.14,
                                    shadowOpacity: 0.08
                                ) {
                                    OnboardingMetricCard(
                                        title: metric.title,
                                        value: metric.value,
                                        systemImage: metric.systemImage,
                                        tint: metric.tint
                                    )
                                }
                            }
                        }

                        OnboardingGlassCard(
                            cornerRadius: 18, fillOpacity: 0.06, strokeOpacity: 0.10,
                            shadowOpacity: 0.06
                        ) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(presentation.footerTitle)
                                    .font(.subheadline.weight(.semibold))

                                Text(presentation.footerSubtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(22)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.16), radius: 24, x: 0, y: 12)
            .accessibilityHidden(true)
        }

        private var backgroundGradient: some View {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(nsColor: .controlBackgroundColor).opacity(0.96),
                        presentation.accentColor.opacity(0.10),
                        Color(nsColor: .controlBackgroundColor).opacity(0.88),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                RadialGradient(
                    colors: [presentation.accentColor.opacity(0.28), .clear],
                    center: .topLeading,
                    startRadius: 20,
                    endRadius: 280
                )
                .blur(radius: 2)

                RadialGradient(
                    colors: [presentation.accentColor.opacity(0.18), .clear],
                    center: .bottomTrailing,
                    startRadius: 20,
                    endRadius: 220
                )
                .blur(radius: 2)
            }
        }

        @ViewBuilder
        private var engineDownloadProgressPanel: some View {
            VStack(spacing: 18) {
                Spacer()

                VStack(spacing: 8) {
                    Text(viewModel.engineDownloadStatusTitle)
                        .font(.system(size: 28, weight: .semibold, design: .rounded))

                    Text(viewModel.engineDownloadProgressLabel)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                ProgressView(value: viewModel.engineDownloadProgress)
                    .progressViewStyle(.linear)
                    .tint(presentation.accentColor)
                    .frame(maxWidth: 280)

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(32)
        }

        private var presentation: StepPresentation {
            switch step {
            case .language:
                return StepPresentation(
                    panelTitle: "Getting ready",
                    panelSubtitle: "The app is getting ready.",
                    heroTitle: "Engine Preparation",
                    heroSubtitle: "Keep this window open while setup finishes.",
                    footerTitle: "Almost there",
                    footerSubtitle: "The setup will finish automatically.",
                    accentColor: .blue,
                    systemImage: "square.and.arrow.down.fill",
                    metrics: [
                        .init(
                            title: "Primary", value: viewModel.transcriptionPrimaryLanguage.uppercased(),
                            systemImage: "character.bubble.fill", tint: .blue),
                        .init(
                            title: "Engine",
                            value: viewModel.transcriptionEngine.displayName,
                            systemImage: "cpu", tint: .green),
                    ]
                )
            case .permissions:
                return StepPresentation(
                    panelTitle: "Grant the basics",
                    panelSubtitle: "Mic and input control remain the only permissions Stet needs.",
                    heroTitle: "Permission ready state",
                    heroSubtitle: viewModel.hasRequiredPermissions
                        ? "Everything required has been detected."
                        : "The onboarding flow still needs microphone and input control permissions.",
                    footerTitle: "Use only what is needed",
                    footerSubtitle: "Permission checks remain exactly where the app expects them.",
                    accentColor: .green,
                    systemImage: "shield.checkerboard",
                    metrics: [
                        .init(
                            title: "Microphone", value: viewModel.microphoneAccessStatusText, systemImage: "mic.fill",
                            tint: viewModel.microphoneAccessNeedsAttention ? .orange : .green),
                        .init(
                            title: "Input control", value: viewModel.autoPasteStatusText, systemImage: "keyboard",
                            tint: viewModel.autoPasteAccessNeedsAttention ? .orange : .green),
                        .init(
                            title: "Ready", value: viewModel.hasRequiredPermissions ? "Yes" : "Needs attention",
                            systemImage: "checkmark.circle.fill",
                            tint: viewModel.hasRequiredPermissions ? .green : .orange),
                    ]
                )
            case .shortcut:
                return StepPresentation(
                    panelTitle: "Set your shortcut",
                    panelSubtitle: "Choose the shortcut you want to use.",
                    heroTitle: viewModel.shortcutSummaryText,
                    heroSubtitle: "The shortcut is ready to use.",
                    footerTitle: "Shortcut setup",
                    footerSubtitle: "The recorder is all you need here.",
                    accentColor: .pink,
                    systemImage: "keyboard",
                    metrics: [
                        .init(
                            title: "Shortcut", value: viewModel.shortcutSummaryText, systemImage: "keyboard",
                            tint: .pink),
                        .init(
                            title: "Next", value: "Continue to first run", systemImage: "arrow.right.circle.fill",
                            tint: .blue),
                        .init(title: "Later", value: "Adjust in Settings", systemImage: "gearshape", tint: .green),
                    ]
                )
            case .firstSuccess:
                return StepPresentation(
                    panelTitle: "Say something in the box",
                    panelSubtitle: "Click the text box, then use your hotkey to speak a sentence.",
                    heroTitle: viewModel.firstSuccessPreviewText ?? "Awaiting first capture",
                    heroSubtitle: viewModel.canContinueFirstSuccessOnboarding
                        ? "A successful result is visible in the box."
                        : "Speak naturally and let the first pass finish.",
                    footerTitle: "Live input check",
                    footerSubtitle: "This step now exercises a real text target.",
                    accentColor: .mint,
                    systemImage: "waveform",
                    metrics: [
                        .init(
                            title: "Result", value: viewModel.firstSuccessPreviewText ?? "No preview yet",
                            systemImage: "text.quote", tint: .mint),
                        .init(
                            title: "Gate", value: viewModel.canContinueFirstSuccessOnboarding ? "Open" : "Waiting",
                            systemImage: "checkmark.circle", tint: .green),
                        .init(
                            title: "Fallback",
                            value: viewModel.canSkipFirstSuccessOnboarding ? "Skip allowed" : "Required",
                            systemImage: "arrow.right.circle", tint: .orange),
                    ]
                )
            case .done:
                return StepPresentation(
                    panelTitle: "Ready to go",
                    panelSubtitle: "Everything needed for the onboarding path is now in place.",
                    heroTitle: "You're all set.",
                    heroSubtitle: "The onboarding path is complete and the app is ready to use.",
                    footerTitle: "Start dictating anywhere",
                    footerSubtitle: "Finish the flow and begin using the app immediately.",
                    accentColor: .purple,
                    systemImage: "checkmark.seal.fill",
                    metrics: [
                        .init(
                            title: "Shortcut", value: viewModel.shortcutSummaryText, systemImage: "keyboard",
                            tint: .purple),
                        .init(
                            title: "Engine",
                            value: viewModel.transcriptionEngine.displayName,
                            systemImage: "cpu", tint: .blue),
                        .init(
                            title: "Permissions",
                            value: viewModel.hasRequiredPermissions ? "Enabled" : "Check required",
                            systemImage: "shield.checkerboard", tint: .green),
                    ]
                )
            default:
                return .empty
            }
        }

        private struct StepPresentation {
            let panelTitle: String
            let panelSubtitle: String
            let heroTitle: String
            let heroSubtitle: String
            let footerTitle: String
            let footerSubtitle: String
            let accentColor: Color
            let systemImage: String
            let metrics: [OnboardingVisualMetric]

            static let empty = StepPresentation(
                panelTitle: "",
                panelSubtitle: "",
                heroTitle: "",
                heroSubtitle: "",
                footerTitle: "",
                footerSubtitle: "",
                accentColor: .accentColor,
                systemImage: "sparkles",
                metrics: []
            )
        }

        private struct OnboardingVisualMetric: Identifiable {
            let id = UUID()
            let title: String
            let value: String
            let systemImage: String
            let tint: Color
        }
    }
#endif
