#if os(macOS)
    import SwiftUI
    import StetCore

    struct MacOpenAISettingsView: View {
        @ObservedObject var viewModel: MacOpenAISettingsViewModel
        var onManageAccount: (() -> Void)? = nil
        private let controlWidth: CGFloat = 240
        @State private var apiKeySheet: APIKeySheetItem?
        @State private var isEditingEndpoint = false
        @State private var credentialError: String?

        var body: some View {
            AppForm {
                Section {
                    VStack(alignment: .leading, spacing: MacUI.SettingsViewMetrics.cardContentSpacing) {
                        Toggle(
                            NSLocalizedString("Transcript improvement", comment: ""), isOn: $viewModel.isRewriteEnabled)

                        Text(
                            NSLocalizedString(
                                "Stet can refine and improve the precision of your transcriptions using AI.",
                                comment: "")
                        )
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                        if viewModel.isRewriteEnabled {
                            Divider().padding(.vertical, 4)

                            MacSettingsValueRow(title: NSLocalizedString("Refine Model", comment: "")) {
                                Picker("", selection: $viewModel.unifiedProvider) {
                                    ForEach(MacOpenAISettingsViewModel.UnifiedAIProvider.allCases) { provider in
                                        Text(
                                            provider.isDisabled
                                                ? "\(provider.displayName) (Unavailable)" : provider.displayName
                                        )
                                        .tag(provider)
                                        .disabled(provider.isDisabled)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .frame(width: controlWidth, alignment: .trailing)
                            }

                            if !viewModel.availableModels.isEmpty {
                                MacSettingsValueRow(title: NSLocalizedString("Preferred Model", comment: "")) {
                                    Picker("", selection: $viewModel.selectedModel) {
                                        ForEach(viewModel.availableModels) { model in
                                            Text(model.displayName).tag(model)
                                        }
                                    }
                                    .labelsHidden()
                                    .pickerStyle(.menu)
                                    .frame(width: controlWidth, alignment: .trailing)
                                }
                            }
                        }
                    }
                } header: {
                    Text(NSLocalizedString("Refine", comment: ""))
                }

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

    private struct MacAPIKeySheet: View {
        let provider: DictationProvider
        @ObservedObject var viewModel: MacOpenAISettingsViewModel
        let onClose: () -> Void
        @State private var draft = ""
        @State private var isVerifying = false
        @State private var verified = false
        @State private var message: String?
        @FocusState private var focused: Bool

        var body: some View {
            MacSettingsEditor(
                title: "\(provider.displayName) API Key",
                subtitle: "Your key is stored securely in Keychain. Verify it to check whether the provider accepts it."
            ) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("API key").font(.subheadline)
                    SecureField("Paste your API key", text: $draft)
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                        .focused($focused)
                        .disabled(isVerifying)
                    if viewModel.hasAPIKey(for: provider) {
                        Text("Current key: \(viewModel.credentialPreview(for: provider))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let message {
                    Label(message, systemImage: verified ? "checkmark.circle" : "info.circle")
                        .font(.callout).foregroundStyle(verified ? Color.primary : Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Button(isVerifying ? "Verifying…" : "Verify Key") {
                        isVerifying = true
                        Task {
                            do {
                                try await viewModel.verifyCredential(draft, for: provider)
                                verified = true
                                message = "Key accepted. Model access may depend on your account."
                            } catch {
                                verified = false
                                message =
                                    "Could not verify this key. Check the key, your connection, and provider access."
                            }
                            isVerifying = false
                        }
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isVerifying)
                    Spacer()
                    Button("Cancel", action: onClose).keyboardShortcut(.cancelAction)
                    Button("Save") {
                        do {
                            try viewModel.storeCredential(draft, for: provider)
                            onClose()
                        } catch {
                            message = "Could not save to Keychain. Please try again."
                            verified = false
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isVerifying)
                }
            }
            .interactiveDismissDisabled(isVerifying)
            .onChange(of: draft) { _, _ in
                verified = false; message = nil
            }
            .onAppear { focused = true }
        }
    }

    private struct MacCustomEndpointSheet: View {
        @ObservedObject var viewModel: MacOpenAISettingsViewModel
        let onClose: () -> Void
        @State private var baseURL = ""
        @State private var key = ""
        @State private var modelID = ""
        @State private var models: [String] = []
        @State private var isLoading = false
        @State private var message: String?

        init(viewModel: MacOpenAISettingsViewModel, onClose: @escaping () -> Void) {
            self.viewModel = viewModel
            self.onClose = onClose
            _baseURL = State(initialValue: Self.singleLineURL(viewModel.customBaseURL))
            _key = State(initialValue: viewModel.customAPIKey)
            _modelID = State(initialValue: viewModel.customModelID)
            _models = State(initialValue: viewModel.discoveredCustomModels)
        }

        private static func singleLineURL(_ value: String) -> String {
            value.components(separatedBy: .newlines).joined()
        }

        private var baseURLBinding: Binding<String> {
            Binding(
                get: { baseURL },
                set: { baseURL = Self.singleLineURL($0) }
            )
        }

        var body: some View {
            MacSettingsEditor(
                title: "Custom Connection", subtitle: "Connect your server, then choose a model for Stet to use."
            ) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Base URL").font(.subheadline)
                    TextField("https://api.example.com/v1", text: baseURLBinding, axis: .horizontal)
                        .lineLimit(1)
                        .labelsHidden()
                    Text("Include the API version path if your provider requires one.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("API key (optional)").font(.subheadline)
                    SecureField("Leave empty for a server without authentication", text: $key).labelsHidden()
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Model").font(.subheadline)
                    Picker("Model", selection: $modelID) {
                        Text(models.isEmpty ? "Verify connection to load models" : "Choose a model").tag("")
                        ForEach(models, id: \.self) { Text($0).tag($0) }
                        if !modelID.isEmpty && !models.contains(modelID) {
                            Text("\(modelID) (saved)").tag(modelID)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .disabled(models.isEmpty)
                }
                if let message {
                    Text(message).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Button(isLoading ? "Checking…" : "Verify & Load Models") {
                        isLoading = true
                        Task {
                            do {
                                models = try await viewModel.discoverModels(baseURL: baseURL, key: key)
                                if !models.contains(modelID) { modelID = "" }
                                message =
                                    models.isEmpty
                                    ? "Connected, but this server returned no models. Check model availability on your server and try again."
                                    : "Connected. Choose a model above, then save."
                            } catch {
                                models = []
                                modelID = ""
                                message =
                                    "Could not load models. Check your server address, API key, and connection, then try again."
                            }
                            isLoading = false
                        }
                    }.disabled(baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                    Spacer()
                    Button("Cancel", action: onClose).keyboardShortcut(.cancelAction)
                    Button("Save") {
                        do {
                            try viewModel.storeCustomEndpoint(
                                baseURL: baseURL, modelID: modelID, key: key, models: models)
                            onClose()
                        } catch { message = "Could not save. Check the server URL and Keychain access." }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(
                        isLoading || baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .textFieldStyle(.roundedBorder)
            .disabled(isLoading)
            .interactiveDismissDisabled(isLoading)
            .onChange(of: baseURL) { _, _ in
                models = []; modelID = ""; message = nil
            }
            .onChange(of: key) { _, _ in
                models = []; modelID = ""; message = nil
            }

        }
    }
#endif
