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
                            Text(viewModel.customBaseURL.isEmpty ? "Not configured" : viewModel.customBaseURL)
                                .font(MacUI.LinearTypography.code)
                                .foregroundStyle(MacUI.Foreground.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        LinearSettingRow("Model") {
                            Text(viewModel.customModelID.isEmpty ? "Not selected" : viewModel.customModelID)
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
                        LocalizedStringKey(
                            String(format: NSLocalizedString("%@ Settings", comment: ""), provider.displayName)
                        )
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
            LinearSettingRow(
                LocalizedStringKey(NSLocalizedString("API key", comment: "")),
                subtitle: viewModel.hasAPIKey(for: provider)
                    ? "Saved securely in Keychain"
                    : provider == .custom
                        ? "Optional for servers without authentication"
                        : "Add a key to connect this provider"
            ) {
                HStack(spacing: 8) {
                    Text(viewModel.credentialPreview(for: provider))
                        .font(MacUI.LinearTypography.code)
                        .foregroundStyle(MacUI.Foreground.secondary)
                    LinearBadge(
                        text: viewModel.hasAPIKey(for: provider) ? "Configured" : "Not set",
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
            Button(
                viewModel.hasAPIKey(for: provider)
                    ? NSLocalizedString("Change…", comment: "")
                    : NSLocalizedString("Set…", comment: "")
            ) {
                apiKeySheet = APIKeySheetItem(provider: provider)
            }
            .buttonStyle(.bordered)

            if viewModel.hasAPIKey(for: provider) {
                Button(NSLocalizedString("Remove", comment: ""), role: .destructive) {
                    do { try viewModel.storeCredential("", for: provider) } catch {
                        credentialError = "The key could not be removed from Keychain. Please try again."
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
