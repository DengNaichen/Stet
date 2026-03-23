#if os(macOS)
import SwiftUI

struct MacOpenAISettingsView: View {
    @ObservedObject var viewModel: MacOpenAISettingsViewModel
    private let controlWidth: CGFloat = 240

    var body: some View {
        AppForm {
            Section {
                VStack(alignment: .leading, spacing: MacUI.SettingsViewMetrics.cardContentSpacing) {
                    MacSettingsValueRow(title: "How to use AI") {
                        Picker("", selection: $viewModel.executionMode) {
                            ForEach(AIExecutionMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: controlWidth, alignment: .trailing)
                    }

                    MacSettingsValueRow(title: "AI service") {
                        Picker("", selection: $viewModel.provider) {
                            ForEach(DictationProvider.allCases) { provider in
                                Text(provider.displayName).tag(provider)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: controlWidth, alignment: .trailing)
                    }

                    MacSettingsValueRow(title: "Status") {
                        MacSettingsStatusBadge(
                            text: viewModel.connectionStatusText,
                            tint: viewModel.connectionNeedsAttention ? .orange : .green
                        )
                        .frame(width: controlWidth, alignment: .trailing)
                    }
                }
            } header: {
                Text("AI setup")
            }

            Section {
                VStack(alignment: .leading, spacing: MacUI.SettingsViewMetrics.cardContentSpacing) {
                    MacSettingsValueRow(title: "Dictation language") {
                        Picker("", selection: $viewModel.dictationLanguageMode) {
                            ForEach(DictationLanguageMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: controlWidth, alignment: .trailing)
                    }

                    Toggle(viewModel.rewriteToggleTitle, isOn: $viewModel.rewriteEnabled)
                }
            } header: {
                Text("Dictation")
            }

            Section {
                VStack(alignment: .leading, spacing: MacUI.SettingsViewMetrics.cardContentSpacing) {
                    SecureField(viewModel.credentialPlaceholder, text: $viewModel.apiKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))

                    HStack(spacing: 12) {
                        Button("Save key") {
                            viewModel.saveCredential()
                        }

                        Button("Remove key", role: .destructive) {
                            viewModel.clearCredential()
                        }
                    }
                }
                .disabled(viewModel.isCredentialEditingDisabled)
            } header: {
                Text(viewModel.credentialFieldTitle)
            }
        }
    }
}
#endif
