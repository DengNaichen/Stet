#if os(macOS)
import SwiftUI

struct MacOpenAISettingsView: View {
    @ObservedObject var viewModel: MacOpenAISettingsViewModel

    var body: some View {
        Form {
            Section {
                LabeledContent("Execution Mode") {
                    Picker("Execution Mode", selection: $viewModel.executionMode) {
                        ForEach(AIExecutionMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 240)
                }

                Text(viewModel.executionModeDescription)
                    .foregroundStyle(.secondary)

                LabeledContent("Provider") {
                    Picker("Provider", selection: $viewModel.provider) {
                        ForEach(DictationProvider.allCases) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 240)
                }

                LabeledContent("Connection") {
                    MacSettingsStatusBadge(
                        text: viewModel.connectionStatusText,
                        tint: viewModel.connectionNeedsAttention ? .orange : .green
                    )
                }
            } header: {
                Text("Provider")
            } footer: {
                Text(viewModel.providerDescription)
            }

            Section {
                LabeledContent("Dictation language") {
                    Picker("Dictation language", selection: $viewModel.dictationLanguageMode) {
                        ForEach(DictationLanguageMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 240)
                }

                Text(viewModel.dictationLanguageDescription)
                    .foregroundStyle(.secondary)

                Toggle(viewModel.rewriteToggleTitle, isOn: $viewModel.rewriteEnabled)

                Toggle(
                    "Translate",
                    isOn: $viewModel.translateSelectedTextOnTranslationHotkey
                )

                LabeledContent("Target language") {
                    Picker("Target language", selection: $viewModel.translationTargetLanguage) {
                        ForEach(TranslationTargetLanguage.allCases) { language in
                            Text(language.title).tag(language)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 240)
                }
            } header: {
                Text("Features")
            } footer: {
                Text(viewModel.modelSummary)
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

                if let missingCredentialMessage = viewModel.missingCredentialMessage {
                    Text(missingCredentialMessage)
                        .foregroundStyle(.orange)
                }

                Text(viewModel.credentialMessage)
                    .foregroundStyle(viewModel.credentialMessageIsError ? .red : .secondary)
            } header: {
                Text(viewModel.credentialFieldTitle)
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 20)
        .padding(.bottom, 28)
    }
}
#endif
