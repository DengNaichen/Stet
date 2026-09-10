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
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    capsulePreview

                    appearanceCoverFlow

                    Text("Choose the color palette used by the dictation capsule.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
                .padding(.vertical, 20)
                .padding(.bottom, MacUI.SettingsViewMetrics.formBottomPadding)
            }
            .macSettingsTracksTitleScroll()
            .task {
                viewModel.load()
            }
        }

        private var capsulePreview: some View {
            MacDictationCapsulePreviewView(
                theme: MacDictationShaderTheme(rawValue: viewModel.shaderTheme.rawValue) ?? .egg,
                scale: 2.0
            )
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 20)
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
            .frame(minHeight: 390)
        }
    }
#endif
