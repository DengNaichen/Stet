import StetAI
import StetCore
import SwiftUI

struct SpeechSettingsDetailView: View {
    @ObservedObject var viewModel: RewriteSettingsViewModel

    var body: some View {
        Form {
            Section {
                Picker(
                    selection: Binding(
                        get: { viewModel.selectedBackend },
                        set: { viewModel.selectedBackend = $0 }
                    )
                ) {
                    ForEach(AppleSpeechTranscriberBackend.allCases) { backend in
                        Text(backend.displayName).tag(backend)
                    }
                } label: {
                    SettingsRowLabel("Engine", systemImage: "cpu")
                }

                Picker(
                    selection: Binding(
                        get: { viewModel.selectedLanguage },
                        set: { viewModel.selectedLanguage = $0 }
                    )
                ) {
                    ForEach(SpeechRecognitionLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                } label: {
                    SettingsRowLabel("Language", systemImage: "globe")
                }

                HStack(spacing: 12) {
                    SettingsRowLabel("Speech Model", systemImage: "waveform")
                    Spacer()
                    speechAssetTrailingView
                }

                if case .failed(let message) = viewModel.speechAssetStatus {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("On-Device Speech")
            } footer: {
                Text(viewModel.selectedBackend.subtitle)
            }
        }
        .navigationTitle("Speech")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.refreshSpeechAssetStatus()
        }
    }

    @ViewBuilder
    private var speechAssetTrailingView: some View {
        switch viewModel.speechAssetStatus {
        case .checking:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Checking")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

        case .installed:
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
                Text("Ready")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

        case .available:
            Button("Download") {
                Task { await viewModel.downloadSpeechAsset() }
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
            .tint(.primary)

        case .downloading:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Downloading")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

        case .unsupportedLocale, .unavailable, .requiresOS26:
            Text("Unsupported")
                .font(.subheadline)
                .foregroundStyle(.secondary)

        case .failed:
            Button("Retry") {
                Task { await viewModel.downloadSpeechAsset() }
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
        }
    }
}

struct MicrophoneSettingsDetailView: View {
    @ObservedObject var viewModel: RewriteSettingsViewModel

    var body: some View {
        Form {
            Section {
                ForEach(MicrophoneKeepAliveDuration.allCases) { duration in
                    let isSelected = viewModel.microphoneKeepAliveDuration == duration
                    Button {
                        viewModel.microphoneKeepAliveDuration = duration
                    } label: {
                        HStack(spacing: 12) {
                            Text(duration.displayName)
                                .foregroundStyle(.primary)
                            Spacer()
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(MobileLinearPalette.accentAmber)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            } header: {
                Text("Auto-Release Mic")
            } footer: {
                Text(viewModel.microphoneKeepAliveDuration.footerDescription)
            }
        }
        .navigationTitle("Microphone")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AIRewriteSettingsDetailView: View {
    @ObservedObject var viewModel: RewriteSettingsViewModel

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $viewModel.settingsStore.isRewriteEnabled) {
                    SettingsRowLabel("AI Polish & Rewrite", systemImage: "sparkles")
                }
                .tint(MobileLinearPalette.accentAmber)
            } header: {
                Text("Cloud Rewrite")
            } footer: {
                Text(
                    "Refines punctuation, removes filler words, and enforces spellings from your Dictionary using your configured API key."
                )
            }

            if viewModel.settingsStore.isRewriteEnabled {
                providerAndModelSection
                apiKeySection
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("AI Rewrite")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.refreshSyncedAPIKey()
        }
    }

    private var providerAndModelSection: some View {
        Section("Provider & Model") {
            Picker(selection: $viewModel.settingsStore.selectedProvider) {
                ForEach(viewModel.availableProviders) { provider in
                    Text(
                        viewModel.isProviderEnabled(provider)
                            ? provider.displayName : "\(provider.displayName) (Unavailable)"
                    )
                    .tag(provider)
                    .disabled(!viewModel.isProviderEnabled(provider))
                }
            } label: {
                SettingsRowLabel("Provider", systemImage: "cloud")
            }
            .onChange(of: viewModel.settingsStore.selectedProvider) {
                viewModel.onProviderChanged()
            }

            if viewModel.settingsStore.selectedProvider == .custom {
                TextField(
                    "https://api.example.com/v1",
                    text: $viewModel.settingsStore.customBaseURL
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)

                if !viewModel.settingsStore.discoveredCustomModels.isEmpty {
                    Picker("Model", selection: $viewModel.settingsStore.customModelID) {
                        ForEach(viewModel.settingsStore.discoveredCustomModels, id: \.self) { modelID in
                            Text(modelID).tag(modelID)
                        }
                        if !viewModel.settingsStore.discoveredCustomModels.contains(
                            viewModel.settingsStore.customModelID),
                            !viewModel.settingsStore.customModelID.isEmpty
                        {
                            Text(viewModel.settingsStore.customModelID).tag(
                                viewModel.settingsStore.customModelID)
                        }
                    }
                }

                TextField("Model ID", text: $viewModel.settingsStore.customModelID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } else if !viewModel.availableModels.isEmpty {
                Picker(selection: Binding(get: { viewModel.selectedModelID }, set: viewModel.selectModel)) {
                    ForEach(viewModel.availableModels) { model in
                        Text(model.displayName).tag(model.id)
                    }
                } label: {
                    SettingsRowLabel("Model", systemImage: "slider.horizontal.3")
                }
            }
        }
    }

    private var apiKeySection: some View {
        Section {
            SecureField(
                viewModel.settingsStore.selectedProvider.apiKeyPlaceholder,
                text: $viewModel.apiKeyInput
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .onSubmit { viewModel.saveAPIKey() }

            Button {
                Task { await viewModel.validateCredential() }
            } label: {
                HStack {
                    Text("Verify & Save Key")
                    Spacer()
                    validationIndicator(viewModel.validationState)
                }
            }
            .disabled(viewModel.validationState == .validating)

            if case .failed(let message) = viewModel.validationState {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("API Key")
        } footer: {
            Text("Synced automatically across your devices via iCloud Keychain.")
        }
    }

    @ViewBuilder
    private func validationIndicator(_ state: RewriteSettingsViewModel.ValidationState) -> some View {
        switch state {
        case .idle:
            EmptyView()
        case .validating:
            ProgressView()
                .controlSize(.small)
        case .success:
            Label("Verified", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }
}

struct AppearanceSettingsDetailView: View {
    @Binding var themeRawValue: String

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14),
    ]

    var body: some View {
        Form {
            Section {
                VStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(selectedTheme.accentColor.opacity(0.18))
                            .frame(width: 144, height: 144)
                            .blur(radius: 20)

                        DictationLevelShaderView(
                            level: 0.32,
                            diameter: 112,
                            preferredFramesPerSecond: 30,
                            isPaused: false,
                            theme: selectedTheme
                        )
                        .shadow(color: selectedTheme.accentColor.opacity(0.26), radius: 18, y: 6)
                    }
                    .frame(height: 140)

                    Text(selectedTheme.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }

            Section {
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(MobileDictationVisualTheme.allCases) { theme in
                        let isSelected = selectedTheme == theme
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 1.0)) {
                                themeRawValue = theme.rawValue
                            }
                        } label: {
                            VStack(spacing: 8) {
                                ZStack {
                                    ThemeOrbSwatch(theme: theme, size: 46)
                                    if isSelected {
                                        Circle()
                                            .strokeBorder(Color.primary, lineWidth: 2.5)
                                            .frame(width: 54, height: 54)
                                    }
                                }
                                .frame(width: 56, height: 56)

                                Text(theme.title)
                                    .font(.caption.weight(isSelected ? .semibold : .regular))
                                    .foregroundStyle(isSelected ? .primary : .secondary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(theme.title) theme")
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
                .padding(.vertical, 8)
            } header: {
                Text("Voice Orb")
            } footer: {
                Text("Applies to the voice orb inside the app.")
            }
        }
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var selectedTheme: MobileDictationVisualTheme {
        MobileDictationVisualTheme(rawValue: themeRawValue) ?? .egg
    }
}
