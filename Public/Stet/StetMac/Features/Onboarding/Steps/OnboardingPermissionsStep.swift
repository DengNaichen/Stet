#if os(macOS)
    import SwiftUI

    struct OnboardingPermissionsStep: View {
        @ObservedObject var viewModel: OnboardingViewModel

        var body: some View {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 14) {
                    PermissionGateRow(
                        title: "Microphone",
                        description: "Used to receive voice input",
                        statusText: viewModel.microphoneAccessStatusText,
                        tint: viewModel.microphoneAccessNeedsAttention ? .orange : .green
                    ) {
                        OnboardingActionButton(
                            title: viewModel.microphonePermissionActionTitle,
                            background: Color.white.opacity(0.08),
                            foreground: .primary,
                            strokeColor: Color.primary.opacity(0.25),
                            minHeight: 44
                        ) {
                            viewModel.resolveMicrophoneAccess()
                        }
                    }

                    PermissionGateRow(
                        title: "Accessibility / Input Control",
                        description: "Used to insert text into active apps",
                        statusText: viewModel.autoPasteStatusText,
                        tint: viewModel.autoPasteAccessNeedsAttention ? .orange : .green
                    ) {
                        HStack(spacing: 8) {
                            OnboardingActionButton(
                                title: "Allow",
                                background: Color.white.opacity(0.08),
                                foreground: .primary,
                                strokeColor: Color.white.opacity(0.10),
                                minHeight: 44
                            ) {
                                viewModel.requestAutoPasteAccess()
                            }

                            OnboardingActionButton(
                                title: "Open Settings",
                                background: Color.white.opacity(0.08),
                                foreground: .primary,
                                strokeColor: Color.white.opacity(0.10),
                                minHeight: 44
                            ) {
                                viewModel.openAccessibilitySettings()
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        Divider()
                            .opacity(0.1)

                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "sparkles")
                                .font(.title2)
                                .foregroundStyle(
                                    {
                                        if #available(macOS 26.0, *) {
                                            return AppleIntelligenceRewriteService.isAvailable
                                                ? Color.purple : Color.secondary
                                        } else {
                                            return Color.secondary
                                        }
                                    }()
                                )
                                .frame(width: 32)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Apple Intelligence")
                                    .font(.headline)

                                if #available(macOS 26.0, *), AppleIntelligenceRewriteService.isAvailable {
                                    Text("Ready to refine your transcriptions.")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text(
                                        {
                                            if #available(macOS 26.0, *) {
                                                return
                                                    "Unavailable: \(AppleIntelligenceRewriteService.availabilityDescription)"
                                            } else {
                                                return "Unavailable on this version of macOS"
                                            }
                                        }()
                                    )
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                    Button("Open Settings") {
                                        if let url = URL(
                                            string: "x-apple.systempreferences:com.apple.AppleIntelligenceSettings")
                                        {
                                            NSWorkspace.shared.open(url)
                                        }
                                    }
                                    .buttonStyle(.link)
                                    .font(.subheadline)
                                }
                            }
                        }
                    }
                    .padding(.top, 4)

                    if viewModel.microphoneAccessNeedsAttention || viewModel.autoPasteAccessNeedsAttention {
                        MessageBanner(
                            text: "Permissions not yet detected. Please authorize in System Settings and return.",
                            role: .warning
                        )
                    }
                }

                Spacer()

                HStack {
                    if viewModel.onboardingMode != nil {
                        OnboardingBackButton { viewModel.retreatOnboarding() }
                    }

                    Spacer()

                    OnboardingActionButton(
                        title: "Continue",
                        isEnabled: viewModel.hasRequiredPermissions,
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
            OnboardingPermissionsStep(
                viewModel: OnboardingViewModel(coordinator: MockOnboardingCoordinator(step: .permissions))
            )
            .frame(width: 440)
            .padding()
        }
    #endif

#endif
