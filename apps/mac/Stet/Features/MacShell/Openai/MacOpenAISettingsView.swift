#if os(macOS)
import SwiftUI

struct MacOpenAISettingsView: View {
    @ObservedObject var viewModel: MacOpenAISettingsViewModel

    var body: some View {
        MacSettingsCard(
            title: "AI Provider",
            description: viewModel.providerDescription
        ) {
            MacSettingsValueRow(title: "Provider") {
                Picker("Provider", selection: $viewModel.provider) {
                    ForEach(DictationProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 220, alignment: .trailing)
            }

            MacSettingsValueRow(title: "Connection") {
                MacSettingsStatusBadge(
                    text: viewModel.connectionStatusText,
                    tint: viewModel.shouldHighlightMissingCredential ? .orange : .green
                )
            }

            Text(viewModel.modelSummary)
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle(viewModel.rewriteToggleTitle, isOn: $viewModel.rewriteEnabled)

            Toggle(
                "Translate selected text directly when the translation shortcut is used",
                isOn: $viewModel.translateSelectedTextOnTranslationHotkey
            )

            MacSettingsValueRow(title: "Target language") {
                Picker("Target language", selection: $viewModel.translationTargetLanguage) {
                    ForEach(TranslationTargetLanguage.allCases) { language in
                        Text(language.title).tag(language)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 220, alignment: .trailing)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(viewModel.credentialFieldTitle)
                    .foregroundStyle(.secondary)

                SecureField(viewModel.credentialPlaceholder, text: $viewModel.apiKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            }

            HStack(spacing: 8) {
                Button("Save Key") {
                    viewModel.saveCredential()
                }

                Button("Clear Key", role: .destructive) {
                    viewModel.clearCredential()
                }
            }
            .controlSize(.regular)

            if viewModel.shouldHighlightMissingCredential {
                Text("Add a \(viewModel.provider.displayName) API key before using cloud transcription, translation, or rewrite.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Text(viewModel.credentialMessage)
                .font(.caption)
                .foregroundStyle(viewModel.credentialMessageIsError ? .red : .secondary)
        }
    }
}
#endif
