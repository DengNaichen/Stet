#if os(macOS)
    import SwiftUI
    import StetCore

    struct MacCustomEndpointSheet: View {
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
                VStack(alignment: .leading, spacing: MacUI.SettingsViewMetrics.labelSpacing) {
                    Text("Base URL").font(MacUI.Typography.fieldLabel)
                    TextField("https://api.example.com/v1", text: baseURLBinding, axis: .horizontal)
                        .lineLimit(1)
                        .labelsHidden()
                    Text("Include the API version path if your provider requires one.")
                        .font(MacUI.Typography.caption).foregroundStyle(MacUI.Foreground.secondary)
                }
                VStack(alignment: .leading, spacing: MacUI.SettingsViewMetrics.labelSpacing) {
                    Text("API key (optional)").font(MacUI.Typography.fieldLabel)
                    SecureField("Leave empty for a server without authentication", text: $key).labelsHidden()
                }
                VStack(alignment: .leading, spacing: MacUI.SettingsViewMetrics.labelSpacing) {
                    Text("Model").font(MacUI.Typography.fieldLabel)
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
                    Text(message).font(MacUI.Typography.status).foregroundStyle(MacUI.Foreground.secondary)
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
