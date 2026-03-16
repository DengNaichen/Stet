#if os(macOS)
import SwiftUI

struct MacOpenAISettingsView: View {
    @EnvironmentObject private var appModel: MacAppModel

    @ObservedObject var viewModel: MacOpenAISettingsViewModel
    @Binding var rewriteEnabled: Bool
    @Binding var openAIBaseURL: String
    @Binding var translationTargetLanguage: TranslationTargetLanguage
    @Binding var translateSelectedTextOnTranslationHotkey: Bool
    @Binding var openAITranslationModel: String

    var body: some View {
        settingsCard(
            title: "OpenAI Pipeline",
            description: "Configure the OpenAI-compatible transcription, translation, and rewrite path. Use the default OpenAI URL for direct BYOK, or point to your managed relay base URL."
        ) {
            settingsValueRow(title: "Transcription") {
                statusBadge(appModel.transcriptionProviderName, tint: .blue)
            }

            Toggle("Rewrite final transcript with OpenAI", isOn: $rewriteEnabled)

            Toggle(
                "Translate selected text directly when the translation shortcut is used",
                isOn: $translateSelectedTextOnTranslationHotkey
            )

            settingsValueRow(title: "Target language") {
                Picker("Target language", selection: $translationTargetLanguage) {
                    ForEach(TranslationTargetLanguage.allCases) { language in
                        Text(language.title).tag(language)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 220, alignment: .trailing)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Translation model")
                    .foregroundStyle(.secondary)

                TextField("OpenAI model for translation", text: $openAITranslationModel)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            }

            settingsValueRow(title: "Status") {
                statusBadge(
                    appModel.openAIStatusText,
                    tint: appModel.openAIStatusText == "Configured" ? .green : .orange
                )
            }

            settingsValueRow(title: "Rewrite") {
                statusBadge(
                    appModel.rewriteStatusText,
                    tint: rewriteEnabled ? .blue : .gray
                )
            }

            settingsValueRow(title: "Translation") {
                statusBadge(translationTargetLanguage.title, tint: .blue)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("OpenAI-compatible base URL")
                    .foregroundStyle(.secondary)

                TextField("https://api.openai.com/v1", text: $openAIBaseURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            }

            HStack(spacing: 8) {
                Button("Use OpenAI Default URL") {
                    openAIBaseURL = MacOpenAISettingsViewModel.defaultBaseURLString
                    openAITranslationModel = "gpt-5-mini"
                }

                Button("Use Groq URL") {
                    openAIBaseURL = MacOpenAISettingsViewModel.groqBaseURLString
                    openAITranslationModel = "llama-3.3-70b-versatile"
                }

                Button("Use Local Relay URL") {
                    openAIBaseURL = MacOpenAISettingsViewModel.localRelayBaseURLString
                    openAITranslationModel = "gpt-5-mini"
                }
            }
            .controlSize(.small)

            Text("Groq uses provider defaults for transcription and rewrite. Current trial defaults: whisper-large-v3-turbo for transcription and llama-3.3-70b-versatile for text generation.")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("OpenAI API key")
                    .foregroundStyle(.secondary)

                SecureField("OpenAI API key or managed access token", text: $viewModel.apiKey)
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
                Text("Add an OpenAI API key or managed access token before using cloud transcription, translation, or rewrite.")
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
