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
                // Keep the complete composition visible in the normal Settings window.
                // Retain scrolling as a fallback for unusually small windows.
                let coverScale = max(
                    0.35,
                    min(0.72, (geometry.size.width - 72) / 440, (geometry.size.height - 140) / 380)
                )

                ScrollView {
                    VStack(spacing: 12) {
                        capsulePreview

                        appearanceCoverFlow
                            .frame(width: 440, height: 380)
                            .scaleEffect(coverScale)
                            .frame(width: 440 * coverScale, height: 380 * coverScale)

                        Text("Choose the appearance of your dictation indicator.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .macSettingsTracksTitleScroll()
            }
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
