#if os(macOS)
import SwiftUI

struct MacOpenAISettingsView: View {
    @ObservedObject var viewModel: MacOpenAISettingsViewModel

    var body: some View {
        settingsCard(
            title: "AI Provider",
            description: viewModel.providerDescription
        ) {
            settingsValueRow(title: "Provider") {
                Picker("Provider", selection: $viewModel.provider) {
                    ForEach(DictationProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 220, alignment: .trailing)
            }

            settingsValueRow(title: "Connection") {
                statusBadge(
                    viewModel.connectionStatusText,
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

            settingsValueRow(title: "Target language") {
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

    @ViewBuilder
    private func settingsCard<Content: View>(
        title: String,
        description: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.headline)

                if let description {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
    }

    @ViewBuilder
    private func settingsValueRow<Value: View>(
        title: String,
        @ViewBuilder value: () -> Value
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            value()
        }
    }

    private func statusBadge(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.12))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(tint.opacity(0.22), lineWidth: 1)
            )
    }
}
#endif
