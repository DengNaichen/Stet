#if os(macOS)
    import SwiftUI
    import StetCore

    struct MacOpenAISettingsView: View {
        @ObservedObject var viewModel: MacOpenAISettingsViewModel
        var onManageAccount: (() -> Void)? = nil
        @State private var apiKeySheet: APIKeySheetItem?
        @State private var isEditingEndpoint = false
        @State private var credentialError: String?

        var body: some View {
            AppForm {
                MacRewriteModelSettingsSection(viewModel: viewModel)

                if viewModel.unifiedProvider == .appleIntelligence {
                    Section {
                        Text(
                            NSLocalizedString(
                                "Uses the on-device Apple Intelligence model to refine transcripts locally. Availability depends on Apple Intelligence being enabled and ready on this Mac.",
                                comment: "")
                        )
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    } header: {
                        Text(NSLocalizedString("Apple Intelligence", comment: ""))
                    }
                }

                if viewModel.isRewriteEnabled, viewModel.unifiedProvider == .custom {
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Connect a service that supports the OpenAI API format.")
                                .font(.callout).foregroundStyle(.secondary)
                            MacSettingsValueRow(title: "Server") {
                                Text(viewModel.customBaseURL.isEmpty ? "Not configured" : viewModel.customBaseURL)
                                    .lineLimit(1).truncationMode(.middle)
                            }
                            MacSettingsValueRow(title: "Model") {
                                Text(viewModel.customModelID.isEmpty ? "Not selected" : viewModel.customModelID)
                                    .lineLimit(1).truncationMode(.middle)
                            }
                            apiKeyStatusRow(for: .custom)
                            Button("Edit Connection…") { isEditingEndpoint = true }
                        }
                    } header: {
                        Text("Custom Endpoint")
                    }
                }

                ForEach(viewModel.visibleCredentialProviders) { provider in
                    Section {
                        VStack(alignment: .leading, spacing: MacUI.SettingsViewMetrics.cardContentSpacing) {
                            apiKeyStatusRow(for: provider)

                            HStack(spacing: 12) {
                                apiKeyActions(for: provider)
                            }
                        }
                    } header: {
                        Text(String(format: NSLocalizedString("%@ Settings", comment: ""), provider.displayName))
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
            MacSettingsValueRow(title: NSLocalizedString("API key", comment: "")) {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(viewModel.credentialPreview(for: provider))
                        .font(.system(.body, design: .monospaced))
                    Text(
                        viewModel.hasAPIKey(for: provider)
                            ? "Saved securely in Keychain"
                            : provider == .custom
                                ? "Optional for servers without authentication" : "Add a key to connect this provider"
                    )
                    .font(.caption).foregroundStyle(.secondary)
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

            if viewModel.hasAPIKey(for: provider) {
                Button(NSLocalizedString("Remove", comment: ""), role: .destructive) {
                    do { try viewModel.storeCredential("", for: provider) } catch {
                        credentialError = "The key could not be removed from Keychain. Please try again."
                    }
                }
                .foregroundStyle(.red)
            }
        }
    }

    private struct APIKeySheetItem: Identifiable {
        let provider: DictationProvider
        var id: String { provider.rawValue }
    }

#endif
