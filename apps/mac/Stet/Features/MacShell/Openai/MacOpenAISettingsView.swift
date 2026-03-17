#if os(macOS)
import SwiftUI

struct MacOpenAISettingsView: View {
    @ObservedObject var viewModel: MacOpenAISettingsViewModel

    var body: some View {
        Form {
            Section {
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
                        tint: viewModel.shouldHighlightMissingCredential ? .orange : .green
                    )
                }
            } header: {
                Text("Provider")
            } footer: {
                Text(viewModel.providerDescription)
            }

            Section {
                Toggle(viewModel.rewriteToggleTitle, isOn: $viewModel.rewriteEnabled)

                Toggle(
                    "Translate selected text directly when the translation shortcut is used",
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

                if viewModel.shouldHighlightMissingCredential {
                    Text("Add a \(viewModel.provider.displayName) API key before using cloud transcription, translation, or rewrite.")
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
