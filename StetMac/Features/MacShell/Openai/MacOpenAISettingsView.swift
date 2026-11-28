import StetAI
#if os(macOS)
    import StetCore
    import SwiftUI

    struct MacSpeechRefineDataFlowNotice: Equatable {
        enum Tone: Equatable {
            case neutral
            case network
        }

        let systemImage: String
        let tone: Tone
        let message: String
        let missingConfigWarning: String?

        static func make(
            isRewriteEnabled: Bool,
            provider: MacOpenAISettingsViewModel.UnifiedAIProvider,
            selectedModelDisplayName: String?,
            customBaseURL: String,
            connectionNeedsAttention: Bool
        ) -> Self {
            guard isRewriteEnabled else {
                return Self(
                    systemImage: "lock.shield",
                    tone: .neutral,
                    message:
                        "Audio is transcribed on your Mac. With AI Refine off, Stet does not send transcripts to an AI provider and only applies local punctuation cleanup.",
                    missingConfigWarning: nil
                )
            }

            switch provider {
            case .appleIntelligence:
                return Self(
                    systemImage: "apple.intelligence",
                    tone: .neutral,
                    message:
                        "Audio transcription and Apple Intelligence refinement both run on your Mac. Availability depends on Apple Intelligence being enabled and ready on this Mac.",
                    missingConfigWarning: nil
                )
            case .custom:
                let destination = Self.customHostLabel(from: customBaseURL)
                let warning =
                    connectionNeedsAttention
                    ? "Custom endpoint isn't fully configured. Until you set a server URL and model, Stet uses on-device transcripts without refinement."
                    : nil
                return Self(
                    systemImage: "network",
                    tone: .network,
                    message:
                        "Audio stays on your Mac. With AI Refine on, Stet sends your raw transcript to \(destination) for cleanup, and can include Personal Dictionary terms, detected language, and active app context when available. If the request fails, Stet falls back to your on-device transcript.",
                    missingConfigWarning: warning
                )
            case .openAI, .google, .deepSeek, .qwen, .glm:
                let providerName = provider.displayName
                let destination: String
                if let modelName = selectedModelDisplayName, !modelName.isEmpty {
                    destination = "\(providerName) (\(modelName))"
                } else {
                    destination = providerName
                }
                let warning =
                    connectionNeedsAttention
                    ? "\(providerName) API key isn't set. Until you add one, Stet uses on-device transcripts without sending text to \(providerName)."
                    : nil
                return Self(
                    systemImage: "network",
                    tone: .network,
                    message:
                        "Audio stays on your Mac. With AI Refine on, Stet sends your raw transcript to \(destination) for cleanup, and can include Personal Dictionary terms, detected language, and active app context when available. If \(providerName) is unavailable, Stet falls back to your on-device transcript.",
                    missingConfigWarning: warning
                )
            }
        }

        private static func customHostLabel(from baseURL: String) -> String {
            let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            if let host = URL(string: trimmed)?.host(), !host.isEmpty {
                return host
            }
            if let host = URL(string: "https://\(trimmed)")?.host(), !trimmed.isEmpty, !host.isEmpty {
                return host
            }
            return "your configured server"
        }
    }

    struct MacRefineSettingsSections: View {
        @ObservedObject var viewModel: MacOpenAISettingsViewModel
        @State private var apiKeySheet: APIKeySheetItem?
        @State private var isEditingEndpoint = false
        @State private var credentialError: String?

        var body: some View {
            let notice = dataFlowNotice

            VStack(alignment: .leading, spacing: MacUI.LinearMetrics.contentSectionSpacing) {
                MacRewriteModelSettingsSection(viewModel: viewModel)

                if let warning = notice.missingConfigWarning {
                    LinearInlineBanner(
                        systemImage: "exclamationmark.triangle.fill",
                        tint: MacUI.Foreground.warning,
                        text: warning
                    )
                    .accessibilityElement(children: .combine)
                }

                LinearInlineBanner(
                    systemImage: notice.systemImage,
                    tint: notice.tone == .network ? MacUI.LinearBrand.accent : MacUI.Foreground.secondaryColor,
                    text: notice.message
                )
                .accessibilityElement(children: .combine)

                if viewModel.isRewriteEnabled, viewModel.unifiedProvider == .custom {
                    LinearSectionGroup(
                        "Custom Endpoint",
                        footer: "Connect a service that supports the OpenAI API format."
                    ) {
                        LinearSettingRow("Server") {
                            Group {
                                if viewModel.customBaseURL.isEmpty {
                                    Text("Not configured")
                                } else {
                                    Text(verbatim: viewModel.customBaseURL)
                                }
                            }
                            .font(MacUI.LinearTypography.code)
                            .foregroundStyle(MacUI.Foreground.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        }

                        LinearSettingRow("Model") {
                            Group {
                                if viewModel.customModelID.isEmpty {
                                    Text("Not selected")
                                } else {
                                    Text(verbatim: viewModel.customModelID)
                                }
                            }
                            .font(MacUI.LinearTypography.code)
                            .foregroundStyle(MacUI.Foreground.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        }

                        apiKeyStatusRow(for: .custom)

                        LinearSettingRow("Connection Settings") {
                            Button("Edit Connection…") { isEditingEndpoint = true }
                                .buttonStyle(.bordered)
                        }
                    }
                }

                ForEach(viewModel.visibleCredentialProviders) { provider in
                    LinearSectionGroup(
                        titleLabel: Text("\(Text(LocalizedStringKey(provider.displayName))) Settings")
                    ) {
                        apiKeyStatusRow(for: provider)

                        LinearSettingRow("Credentials") {
                            HStack(spacing: 8) {
                                apiKeyActions(for: provider)
                            }
                        }
                    }
                }
            }
            .macSettingsSheet(
                isPresented: Binding(
                    get: { apiKeySheet != nil }, set: { if !$0 { apiKeySheet = nil } }
                )
            ) {
                if let item = apiKeySheet {
                    MacAPIKeySheet(provider: item.provider, viewModel: viewModel) { apiKeySheet = nil }
                }
            }
            .macSettingsSheet(isPresented: $isEditingEndpoint) {
                MacCustomEndpointSheet(viewModel: viewModel) { isEditingEndpoint = false }
            }
            .alert(
                "Could not update API key",
                isPresented: Binding(
                    get: { credentialError != nil }, set: { if !$0 { credentialError = nil } }
                )
            ) {
                Button("OK", role: .cancel) { credentialError = nil }
            } message: {
                Text(credentialError ?? "")
            }
        }

        private var dataFlowNotice: MacSpeechRefineDataFlowNotice {
            let modelName = viewModel.availableModels.first(where: { $0.id == viewModel.selectedModelID })?.displayName
            return MacSpeechRefineDataFlowNotice.make(
                isRewriteEnabled: viewModel.isRewriteEnabled,
                provider: viewModel.unifiedProvider,
                selectedModelDisplayName: modelName,
                customBaseURL: viewModel.customBaseURL,
                connectionNeedsAttention: viewModel.connectionNeedsAttention
            )
        }

        private func apiKeyStatusRow(for provider: DictationProvider) -> some View {
            let subtitle: LocalizedStringKey =
                viewModel.hasAPIKey(for: provider)
                ? "Saved securely in Keychain"
                : provider == .custom
                    ? "Optional for servers without authentication"
                    : "Add a key to connect this provider"
            let badgeText: LocalizedStringKey = viewModel.hasAPIKey(for: provider) ? "Configured" : "Not set"
            return LinearSettingRow(
                "API key",
                subtitle: subtitle
            ) {
                HStack(spacing: 8) {
                    Group {
                        if viewModel.hasAPIKey(for: provider) {
                            Text(verbatim: viewModel.credentialPreview(for: provider))
                        } else {
                            Text("Not configured")
                        }
                    }
                    .font(MacUI.LinearTypography.code)
                    .foregroundStyle(MacUI.Foreground.secondary)
                    LinearBadge(
                        text: badgeText,
                        tint: viewModel.hasAPIKey(for: provider)
                            ? MacUI.Foreground.success
                            : MacUI.Foreground.secondaryColor,
                        showDot: viewModel.hasAPIKey(for: provider)
                    )
                }
            }
        }

        @ViewBuilder
        private func apiKeyActions(for provider: DictationProvider) -> some View {
            let actionTitle: LocalizedStringKey = viewModel.hasAPIKey(for: provider) ? "Change…" : "Set…"
            Button(actionTitle) {
                apiKeySheet = APIKeySheetItem(provider: provider)
            }
            .buttonStyle(.bordered)

            if viewModel.hasAPIKey(for: provider) {
                Button("Remove", role: .destructive) {
                    do { try viewModel.storeCredential("", for: provider) } catch {
                        credentialError = String(
                            localized: "The key could not be removed from Keychain. Please try again.")
                    }
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private struct APIKeySheetItem: Identifiable {
        let provider: DictationProvider
        var id: String { provider.rawValue }
    }
#endif
