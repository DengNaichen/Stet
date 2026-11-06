#if os(macOS)
    import SwiftUI
    import StetCore

    struct MacAPIKeySheet: View {
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

#endif
