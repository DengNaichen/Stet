#if os(macOS)
    import StetVisuals
    import SwiftUI

    struct MacAppearanceSettingsView: View {
        @StateObject private var viewModel: MacAppearanceSettingsViewModel

        init() {
            _viewModel = StateObject(wrappedValue: .shared)
        }

        init(viewModel: MacAppearanceSettingsViewModel) {
            _viewModel = StateObject(wrappedValue: viewModel)
        }

        var body: some View {
            GeometryReader { geometry in
                let coverScale = max(
                    0.35,
                    min(0.72, (geometry.size.width - 64) / 440, (geometry.size.height - 124) / 380)
                )

                ScrollView {
                    VStack(spacing: 14) {
                        LinearSectionGroup(
                            "Dictation Indicator",
                            footer: "Choose the appearance of your dictation indicator."
                        ) {
                            VStack(spacing: 10) {
                                capsulePreview
                                appearanceCoverFlow
                                    .frame(width: 440, height: 380)
                                    .scaleEffect(coverScale)
                                    .frame(width: 440 * coverScale, height: 380 * coverScale)
                            }
                            .padding(.vertical, 16)
                            .padding(.horizontal, 12)
                            .frame(maxWidth: .infinity)
                        }
                        .id(MacSettingsTargetSection.dictationIndicator)
                    }
                    .frame(maxWidth: MacUI.LinearMetrics.contentMaxWidth)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, MacUI.LinearMetrics.contentHorizontalPadding)
                    .padding(.top, MacUI.LinearMetrics.contentTopPadding)
                    .padding(.bottom, MacUI.LinearMetrics.contentBottomPadding)
                }
                .macSettingsScrollIndicator()
            }
            .macNativeNavigationChrome(title: "Appearance")
            .task {
                viewModel.load()
            }
        }

        private var capsulePreview: some View {
            MacDictationCapsulePreviewView(
                theme: MacDictationShaderTheme(rawValue: viewModel.shaderTheme.rawValue) ?? .watercolor,
                scale: 1.1
            )
            .frame(maxWidth: .infinity, alignment: .center)
        }

        private var appearanceCoverFlow: some View {
            OnboardingAppearanceCoverFlowPanel(
                selectedTheme: viewModel.shaderTheme,
                isSelectedThemeApplied: viewModel.hasAppliedSelectedTheme,
                onFocusedThemeChange: { theme in
                    viewModel.updateShaderTheme(theme, persist: true)
                },
                onApplyTheme: { theme in
                    viewModel.updateShaderTheme(theme, persist: true)
                }
            )
        }
    }
#endif
