#if os(macOS)
    import SwiftUI

    struct OnboardingPermissionsStep: View {
        @ObservedObject var viewModel: OnboardingViewModel

        var body: some View {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 18) {
                    OnboardingStepHeader(
                        eyebrow: "Step 2 of 5",
                        title: "Grant two macOS permissions",
                        subtitle: "Stet only asks for what dictation requires. Audio never leaves your Mac."
                    )

                    LinearSectionGroup {
                        permissionRow(
                            systemImage: "mic",
                            title: "Microphone",
                            subtitle: "Listen while your dictation shortcut is active.",
                            isGranted: !viewModel.microphoneAccessNeedsAttention
                        ) {
                            OnboardingSecondaryButton(
                                verbatim: viewModel.microphonePermissionActionTitle,
                                isCompact: true
                            ) {
                                viewModel.resolveMicrophoneAccess()
                            }
                        }

                        LinearHairlineDivider(insetLeading: 58)

                        permissionRow(
                            systemImage: "keyboard",
                            title: "Input Control",
                            subtitle: "Insert transcribed text directly into the app you're using.",
                            isGranted: !viewModel.autoPasteAccessNeedsAttention
                        ) {
                            HStack(spacing: 6) {
                                OnboardingSecondaryButton("Allow", isCompact: true) {
                                    viewModel.requestAutoPasteAccess()
                                }

                                OnboardingSecondaryButton("Open Settings", isCompact: true) {
                                    viewModel.openAccessibilitySettings()
                                }
                            }
                        }
                    }

                    if !viewModel.hasRequiredPermissions {
                        LinearInlineBanner(
                            systemImage: "info.circle",
                            tint: MacUI.LinearBrand.accent,
                            message: "Permissions not yet detected. Authorize both in System Settings and return here."
                        )
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, OnboardingMetrics.contentHorizontalPadding)
                .padding(.top, 4)
                .padding(.bottom, 16)

                OnboardingFooterBar {
                    OnboardingBackButton {
                        viewModel.retreatOnboarding()
                    }
                } trailing: {
                    OnboardingPrimaryButton(
                        "Continue",
                        isEnabled: viewModel.hasRequiredPermissions
                    ) {
                        viewModel.continueOnboarding()
                    }
                }
            }
        }

        private func permissionRow<Actions: View>(
            systemImage: String,
            title: LocalizedStringKey,
            subtitle: LocalizedStringKey,
            isGranted: Bool,
            @ViewBuilder actions: () -> Actions
        ) -> some View {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isGranted ? MacUI.Foreground.success : MacUI.Foreground.primary)
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isGranted ? MacUI.Foreground.success.opacity(0.11) : MacUI.LinearSurfaces.elevated)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(
                                isGranted ? MacUI.Foreground.success.opacity(0.25) : MacUI.LinearSurfaces.hairline,
                                lineWidth: 1
                            )
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(MacUI.Foreground.primary)

                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(MacUI.Foreground.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                if isGranted {
                    OnboardingStatusPill("Granted")
                } else {
                    actions()
                }
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 13)
            .frame(minHeight: 58)
        }
    }

    #if DEBUG
        #Preview {
            OnboardingPermissionsStep(
                viewModel: OnboardingViewModel(coordinator: MockOnboardingCoordinator(step: .permissions))
            )
            .frame(width: OnboardingMetrics.windowWidth, height: 500)
        }
    #endif
#endif
