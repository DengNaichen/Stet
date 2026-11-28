#if os(macOS)
    import StetVisuals
    import SwiftUI

    struct OnboardingAppearanceStep: View {
        @ObservedObject var viewModel: OnboardingViewModel
        @ObservedObject var appearanceViewModel: MacAppearanceSettingsViewModel

        private var selectedTheme: MacDictationVisualTheme {
            viewModel.onboardingPreviewTheme
        }

        private var selectedShaderTheme: MacDictationShaderTheme {
            MacDictationShaderTheme(rawValue: selectedTheme.rawValue) ?? .watercolor
        }

        var body: some View {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 16) {
                    OnboardingStepHeader(
                        eyebrow: "Step 5 of 5",
                        title: "Choose your dictation orb",
                        subtitle: "Pick a watercolor palette for your floating indicator. You can change it anytime."
                    )

                    orbShowcaseCard

                    themeStrip
                }
                .padding(.horizontal, OnboardingMetrics.contentHorizontalPadding)
                .padding(.top, 4)
                .padding(.bottom, 16)

                OnboardingFooterBar {
                    OnboardingBackButton {
                        viewModel.retreatOnboarding()
                    }
                } trailing: {
                    OnboardingPrimaryButton("Apply & Finish") {
                        viewModel.applyOnboardingAppearanceTheme()
                        viewModel.finishOnboarding()
                    }
                }
            }
            .onAppear {
                appearanceViewModel.load()
                viewModel.selectOnboardingAppearanceTheme(appearanceViewModel.shaderTheme)
            }
        }

        private var orbShowcaseCard: some View {
            let swatches = OnboardingPalette.themeSwatches(for: selectedTheme)
            let washColor = swatches.last ?? MacUI.LinearBrand.accent

            return ZStack {
                RadialGradient(
                    colors: [washColor.opacity(0.16), .clear],
                    center: UnitPoint(x: 0.5, y: 0.44),
                    startRadius: 10,
                    endRadius: 170
                )
                .animation(.easeInOut(duration: 0.35), value: selectedTheme)

                VStack(spacing: 14) {
                    ZStack {
                        Capsule(style: .continuous)
                            .fill(OnboardingPalette.capsuleSurface)
                            .frame(width: 144, height: 76)
                            .overlay(
                                Capsule(style: .continuous)
                                    .strokeBorder(MacUI.LinearSurfaces.hairline, lineWidth: 1)
                            )
                            .shadow(color: Color.black.opacity(0.12), radius: 18, x: 0, y: 8)

                        MacDictationCapsulePreviewView(
                            theme: selectedShaderTheme,
                            scale: 0.94
                        )
                    }

                    Text(LocalizedStringKey(selectedTheme.title))
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(MacUI.Foreground.primary)
                }
                .padding(20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(MacUI.LinearSurfaces.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(MacUI.LinearSurfaces.hairline, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }

        private var themeStrip: some View {
            let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
            return LazyVGrid(columns: columns, spacing: 6) {
                ForEach(MacDictationVisualTheme.allCases) { theme in
                    let isSelected = theme == selectedTheme
                    let swatches = OnboardingPalette.themeSwatches(for: theme)

                    Button {
                        withAnimation(.easeOut(duration: 0.2)) {
                            viewModel.selectOnboardingAppearanceTheme(theme)
                        }
                    } label: {
                        VStack(spacing: 7) {
                            Circle()
                                .fill(
                                    RadialGradient(
                                        colors: [
                                            swatches[1],
                                            swatches[0],
                                            swatches[2],
                                        ],
                                        center: UnitPoint(x: 0.32, y: 0.28),
                                        startRadius: 1,
                                        endRadius: 18
                                    )
                                )
                                .frame(width: 28, height: 28)
                                .overlay(
                                    Circle()
                                        .strokeBorder(Color.white.opacity(0.35), lineWidth: 0.75)
                                )
                                .shadow(color: Color.black.opacity(0.14), radius: 4, x: 0, y: 2)

                            Text(OnboardingPalette.shortTitle(for: theme))
                                .font(.system(size: 10.5, weight: isSelected ? .semibold : .medium))
                                .foregroundStyle(
                                    isSelected ? MacUI.Foreground.primary : MacUI.Foreground.secondaryColor
                                )
                                .lineLimit(1)
                        }
                        .padding(.vertical, 9)
                        .padding(.horizontal, 4)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(isSelected ? OnboardingPalette.accentSoft : MacUI.LinearSurfaces.card)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(
                                    isSelected ? MacUI.LinearBrand.accent : MacUI.LinearSurfaces.hairline,
                                    lineWidth: isSelected ? 1.5 : 1
                                )
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    #if DEBUG
        #Preview {
            OnboardingAppearanceStep(
                viewModel: OnboardingViewModel(
                    coordinator: MockOnboardingCoordinator(step: .appearance)
                ),
                appearanceViewModel: .shared
            )
            .frame(width: OnboardingMetrics.windowWidth, height: 500)
        }
    #endif
#endif
