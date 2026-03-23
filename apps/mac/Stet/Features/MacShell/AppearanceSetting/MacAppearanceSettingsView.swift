#if os(macOS)
import SwiftUI

struct MacAppearanceSettingsView: View {
    @StateObject private var viewModel = MacAppearanceSettingsViewModel()

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
            Picker("Capsule Theme", selection: $viewModel.shaderTheme) {
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
}
#endif
