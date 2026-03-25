#if os(macOS)
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
            Form {
                appearanceSection
            }
            .formStyle(.grouped)
            .padding(.horizontal, MacUI.SettingsViewMetrics.formHorizontalPadding)
            .padding(.bottom, MacUI.SettingsViewMetrics.formBottomPadding)
            .task {
                viewModel.load()
            }
        }

        private var appearanceSection: some View {
            Section {
                Picker("Capsule Theme", selection: shaderThemeBinding) {
                    ForEach(MacDictationVisualTheme.allCases) { theme in
                        Text(theme.title).tag(theme)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text("Appearance")
            } footer: {
                Text("Choose the color palette used by the dictation capsule.")
            }
        }

        private var shaderThemeBinding: Binding<MacDictationVisualTheme> {
            Binding(
                get: { viewModel.shaderTheme },
                set: { viewModel.updateShaderTheme($0, persist: true) }
            )
        }
    }
#endif
