#if os(macOS)
import SwiftUI

struct MacOpenAISettingsView: View {
    @ObservedObject var viewModel: MacOpenAISettingsViewModel
    private let controlWidth: CGFloat = 240

    var body: some View {
        AppForm {
            Section {
                MacSettingsValueRow(title: "Execution Mode") {
                    Picker("", selection: $viewModel.executionMode) {
                        ForEach(AIExecutionMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: controlWidth, alignment: .trailing)
                }

                MacSettingsValueRow(title: "Provider") {
                    Picker("", selection: $viewModel.provider) {
                        ForEach(DictationProvider.allCases) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: controlWidth, alignment: .trailing)
                }

                MacSettingsValueRow(title: "Connection") {
                    MacSettingsStatusBadge(
                        text: viewModel.connectionStatusText,
                        tint: viewModel.connectionNeedsAttention ? .orange : .green
                    )
                    .frame(width: controlWidth, alignment: .trailing)
                }
            } header: {
                Text("Provider")
            }

            Section {
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
            } header: {
                Text("Features")
            }

            Section {
                Group {
                    SecureField(viewModel.credentialPlaceholder, text: $viewModel.apiKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))

                    HStack(spacing: 10) {
                        Button("Save Key") {
                            viewModel.saveCredential()
                        }

                        Button("Clear Key", role: .destructive) {
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
