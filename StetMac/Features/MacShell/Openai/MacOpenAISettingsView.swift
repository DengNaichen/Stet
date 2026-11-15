#if os(macOS)
    import StetCore
    import SwiftUI

    struct MacOpenAISettingsView: View {
        @ObservedObject var viewModel: MacOpenAISettingsViewModel
        var onManageAccount: (() -> Void)? = nil
        @State private var apiKeySheet: APIKeySheetItem?
        @State private var isEditingEndpoint = false
        @State private var credentialError: String?

        var body: some View {
            LinearPageContainer(title: "Refine") {
                MacRewriteModelSettingsSection(viewModel: viewModel)

                if viewModel.unifiedProvider == .appleIntelligence {
                    LinearInlineBanner(
                        systemImage: "apple.intelligence",
                        tint: MacUI.Foreground.secondaryColor,
                        message:
                            "Uses the on-device Apple Intelligence model to refine transcripts locally. Availability depends on Apple Intelligence being enabled and ready on this Mac."
                    )
                }

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
            .onAppear {
                viewModel.load()
            }
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
