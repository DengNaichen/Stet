#if os(macOS)
    import SwiftUI

    struct OnboardingLanguageStep: View {
        @ObservedObject var viewModel: OnboardingViewModel
        @State private var showingSecondaryLanguage = false

        private let languages = [
            ("English", "en"),
            ("Chinese (Simplified)", "zh-Hans"),
            ("Chinese (Traditional)", "zh-Hant"),
            ("Japanese", "ja"),
            ("Korean", "ko"),
            ("French", "fr"),
            ("German", "de"),
            ("Spanish", "es"),
            ("Portuguese", "pt"),
            ("Italian", "it"),
        ]

        var body: some View {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Primary Language")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    Picker("Primary Language", selection: $viewModel.transcriptionPrimaryLanguage) {
                        ForEach(languages, id: \.1) { name, code in
                            Text(name).tag(code)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Secondary Language (Optional)")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        Spacer()

                        if viewModel.transcriptionSecondaryLanguage == nil {
                            Button {
                                viewModel.transcriptionSecondaryLanguage = "zh-Hans"
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(.blue)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Button {
                                viewModel.transcriptionSecondaryLanguage = nil
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if viewModel.transcriptionSecondaryLanguage != nil {
                        Picker(
                            "Secondary Language",
                            selection: Binding(
                                get: { viewModel.transcriptionSecondaryLanguage ?? "zh-Hans" },
                                set: { viewModel.transcriptionSecondaryLanguage = $0 }
                            )
                        ) {
                            ForEach(languages, id: \.1) { name, code in
                                Text(name).tag(code)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Text("Stet will automatically detect between these two languages.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Add a second language if you often switch between them while speaking.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        Image(systemName: viewModel.transcriptionEngine == .fluidAudio ? "bolt.fill" : "cpu")
                            .font(.title2)
                            .foregroundStyle(.blue)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(
                                "Engine: \(viewModel.transcriptionEngine == .fluidAudio ? "Parakeet V3" : "Whisper Large")"
                            )
                            .font(.subheadline)
                            .fontWeight(.medium)
                            Text(
                                viewModel.transcriptionEngine == .fluidAudio
                                    ? "Optimized for speed and accuracy in these languages."
                                    : "Highly accurate multilingual engine."
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(12)
                }

                if case .failed(let message) = viewModel.engineDownloadState {
                    MessageBanner(text: message, role: .error)
                }

                Spacer()

                VStack(spacing: 12) {
                    if viewModel.isEngineDownloadRunning {
                        VStack(spacing: 8) {
                            ProgressView(value: viewModel.engineDownloadProgress)
                                .progressViewStyle(.linear)

                            HStack {
                                Text(viewModel.engineDownloadProgressLabel)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                        }
                    }

                    OnboardingActionButton(
                        title: viewModel.engineDownloadPrimaryButtonTitle,
                        isEnabled: !viewModel.isEngineDownloadRunning,
                        minHeight: 48
                    ) {
                        Task {
                            await viewModel.handleEngineDownloadPrimaryAction()
                        }
                    }
                }
            }
        }
    }

    #if DEBUG
        #Preview {
            OnboardingLanguageStep(
                viewModel: OnboardingViewModel(coordinator: MockOnboardingCoordinator(step: .language))
            )
            .frame(width: 440, height: 400)
            .padding()
        }
    #endif
#endif
