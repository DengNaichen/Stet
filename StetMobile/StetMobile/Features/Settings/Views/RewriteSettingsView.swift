import StetAI
import StetCore
import SwiftUI

struct RewriteSettingsView: View {
    @ObservedObject var viewModel: RewriteSettingsViewModel
    @AppStorage(
        MobileDictationVisualTheme.mobileStorageKey,
        store: MobileDictationVisualTheme.mobileDefaults
    ) private var themeRawValue = MobileDictationVisualTheme.egg.rawValue

    var body: some View {
        NavigationStack {
            Form {
                onDeviceSpeechSection
                aiRewriteSection
                orbAppearanceSection
            }
            .scrollDismissesKeyboard(.interactively)
            .linearInlineHeader("Settings")
            .onAppear {
                viewModel.refreshSyncedAPIKey()
            }
            .task {
                await viewModel.refreshSpeechAssetStatus()
            }
        }
    }

    private var onDeviceSpeechSection: some View {
        Section {
            Picker(
                selection: Binding(
                    get: { viewModel.selectedBackend },
                    set: { viewModel.selectedBackend = $0 }
                )
            ) {
                ForEach(SpeechTranscriberBackend.allCases) { backend in
                    Text(backend.displayName).tag(backend)
                }
            } label: {
                settingsLabel("Engine", systemImage: "cpu")
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
                settingsLabel("Language", systemImage: "globe")
            }

            HStack(spacing: 12) {
                settingsLabel("Speech Model", systemImage: "waveform")
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

        case .unsupported:
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

    private var aiRewriteSection: some View {
        Group {
            Section {
                Toggle(isOn: $viewModel.settingsStore.isRewriteEnabled) {
                    settingsLabel("AI Polish & Rewrite", systemImage: "sparkles")
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
                Section("Provider & Model") {
                    Picker(selection: $viewModel.settingsStore.selectedProvider) {
                        ForEach(viewModel.availableProviders) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    } label: {
                        settingsLabel("Provider", systemImage: "cloud")
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
                    } else {
                        Picker(selection: $viewModel.settingsStore.selectedModel) {
                            ForEach(RewriteModel.availableModels(for: viewModel.settingsStore.selectedProvider)) {
                                model in
                                Text(model.displayName).tag(model)
                            }
                        } label: {
                            settingsLabel("Model", systemImage: "slider.horizontal.3")
                        }
                    }
                }

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
        }
    }

    private var orbAppearanceSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(MobileDictationVisualTheme.allCases) { theme in
                        let isSelected = selectedTheme == theme
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 1.0)) {
                                themeRawValue = theme.rawValue
                            }
                        } label: {
                            VStack(spacing: 8) {
                                ZStack {
                                    ThemeOrbSwatch(theme: theme, size: 42)
                                    if isSelected {
                                        Circle()
                                            .strokeBorder(Color.primary, lineWidth: 2.5)
                                            .frame(width: 50, height: 50)
                                    }
                                }
                                .frame(width: 52, height: 52)

                                Text(theme.title)
                                    .font(.caption.weight(isSelected ? .semibold : .regular))
                                    .foregroundStyle(isSelected ? .primary : .secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(theme.title) theme")
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
                .padding(.vertical, 6)
            }
        } header: {
            Text("Voice Orb")
        } footer: {
            Text("Applies to the voice orb inside the app.")
        }
    }

    private func settingsLabel(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .center)
            Text(title)
                .foregroundStyle(.primary)
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

    private var selectedTheme: MobileDictationVisualTheme {
        MobileDictationVisualTheme(rawValue: themeRawValue) ?? .egg
    }
}
