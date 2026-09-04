#if os(macOS)
    import SwiftUI
    import StetCore

    struct MacAudioSettingsView: View {
        @StateObject private var viewModel = MacAudioSettingsViewModel()

        var body: some View {
            Form {
                AudioInputDeviceSettingsSection(
                    deviceManager: viewModel.deviceManager,
                    microphoneTestViewModel: viewModel.microphoneTestViewModel
                )
                Section {
                    VStack(alignment: .leading, spacing: MacUI.SettingsViewMetrics.cardContentSpacing) {
                        Text("Choose which on-device model handles transcription.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)

                        MacSettingsValueRow(title: "Engine") {
                            Picker("", selection: $viewModel.localTranscriptionEngine) {
                                ForEach(viewModel.localTranscriptionEngineOptions, id: \.self) { engine in
                                    Text(engine.displayName).tag(engine)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(width: 240, alignment: .trailing)
                        }

                        if viewModel.localTranscriptionEngine == .fluidAudio, !viewModel.isParakeetDownloaded {
                            Text(
                                "Parakeet model isn't downloaded yet. Stet will fall back to Whisper until you download it below."
                            )
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                        }

                        if viewModel.localTranscriptionEngine == .funASRNano,
                            !viewModel.isFunASRNanoDownloaded
                        {
                            Text(
                                "Fun-ASR Nano isn't downloaded yet. Stet will fall back to Whisper until you download it below."
                            )
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                        }

                        Divider().padding(.vertical, 4)

                        // Models Management
                        VStack(spacing: 12) {
                            TranscriptionModelRow(
                                name: "Whisper",
                                isDownloaded: viewModel.isWhisperDownloaded,
                                isDownloading: viewModel.isWhisperDownloading,
                                errorMessage: viewModel.whisperErrorMessage,
                                onDownload: { viewModel.downloadWhisperModel() },
                                onReveal: { viewModel.openWhisperFolder() }
                            )

                            Divider()

                            TranscriptionModelRow(
                                name: "Parakeet V3",
                                isDownloaded: viewModel.isParakeetDownloaded,
                                isDownloading: viewModel.isParakeetDownloading,
                                errorMessage: viewModel.parakeetErrorMessage,
                                onDownload: { viewModel.downloadParakeetModel() },
                                onReveal: { viewModel.openParakeetFolder() }
                            )

                            Divider()

                            TranscriptionModelRow(
                                name: "Fun-ASR Nano (Chinese / English / Japanese)",
                                isDownloaded: viewModel.isFunASRNanoDownloaded,
                                isDownloading: viewModel.isFunASRNanoDownloading,
                                errorMessage: viewModel.funASRNanoErrorMessage,
                                onDownload: { viewModel.downloadFunASRNanoModel() },
                                onReveal: { viewModel.openFunASRNanoFolder() }
                            )
                        }
                    }
                } header: {
                    Text("Local Transcription")
                }

                Section("Passive Transcription") {
                    VStack(alignment: .leading, spacing: MacUI.SettingsViewMetrics.cardContentSpacing) {
                        Toggle("Enable passive transcription", isOn: $viewModel.isPassiveListeningEnabled)

                        Text(
                            "When enabled, Stet listens locally for conversations that include your enrolled voice. Turning it off stops passive microphone capture; active hotkey dictation remains available."
                        )
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    }
                }

                Section("Speaker Profiles") {
                    VStack(alignment: .leading, spacing: MacUI.SettingsViewMetrics.cardContentSpacing) {
                        Text(MacAudioSettingsViewModel.speakerEnrollmentConsentCopy)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)

                        if viewModel.speakerProfiles.isEmpty {
                            Text("No speaker profiles enrolled.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(viewModel.speakerProfiles) { profile in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(profile.displayName)
                                        Text(profile.role == .owner ? "Owner" : "Known speaker")
                                            .font(.system(size: 10))
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if profile.status == .requiresReenrollment {
                                        Text("Re-enroll required")
                                            .font(.system(size: 10))
                                            .foregroundStyle(.orange)
                                    }
                                    Button("Delete", role: .destructive) {
                                        Task { await viewModel.deleteSpeakerProfile(id: profile.id) }
                                    }
                                    .accessibilityLabel("Delete speaker profile for \(profile.displayName)")
                                }
                            }
                        }

                        Divider().padding(.vertical, 4)

                        Picker("Profile", selection: $viewModel.enrollmentRole) {
                            Text("Me").tag(SpeakerProfileRole.owner)
                            Text("Known speaker").tag(SpeakerProfileRole.known)
                        }
                        .pickerStyle(.segmented)
                        .disabled(viewModel.enrollmentClipCount > 0 || viewModel.isRecordingEnrollment)

                        MacSettingsValueRow(
                            title: viewModel.enrollmentRole == .owner ? "Your name" : "Speaker name"
                        ) {
                            TextField(
                                viewModel.enrollmentRole == .owner ? "Me" : "Name",
                                text: $viewModel.enrollmentName
                            )
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 240)
                            .disabled(viewModel.enrollmentClipCount > 0 || viewModel.isRecordingEnrollment)
                        }

                        if viewModel.enrollmentRole == .known {
                            Toggle(
                                "I have permission to record and enroll this speaker.",
                                isOn: $viewModel.hasSpeakerEnrollmentConsent
                            )
                            .disabled(viewModel.enrollmentClipCount > 0 || viewModel.isRecordingEnrollment)
                        }

                        HStack(spacing: 10) {
                            Button {
                                Task {
                                    if viewModel.isRecordingEnrollment {
                                        await viewModel.stopSpeakerEnrollmentClip()
                                    } else {
                                        await viewModel.startSpeakerEnrollmentClip()
                                    }
                                }
                            } label: {
                                Label(
                                    viewModel.isRecordingEnrollment ? "Stop sample" : "Record sample",
                                    systemImage: viewModel.isRecordingEnrollment
                                        ? "stop.circle.fill" : "record.circle"
                                )
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(viewModel.isRecordingEnrollment ? .red : .accentColor)
                            .disabled(
                                viewModel.isProcessingEnrollment
                                    || (!viewModel.isRecordingEnrollment && !viewModel.canStartSpeakerEnrollment)
                            )

                            Text(
                                "\(viewModel.enrollmentClipCount) of \(MacAudioSettingsViewModel.requiredEnrollmentClipCount) samples"
                            )
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)

                            if viewModel.isProcessingEnrollment {
                                ProgressView()
                                    .controlSize(.small)
                                    .accessibilityLabel("Processing speaker sample")
                            }
                        }

                        if let message = viewModel.enrollmentErrorMessage {
                            Text(message)
                                .font(.system(size: 10))
                                .foregroundStyle(.red)
                        } else if let message = viewModel.enrollmentCompletionMessage {
                            Text(message)
                                .font(.system(size: 10))
                                .foregroundStyle(.green)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .padding(.leading, MacUI.SettingsViewMetrics.formHorizontalPadding)
            .padding(.bottom, MacUI.SettingsViewMetrics.formBottomPadding)
            .task {
                viewModel.onAppear()
                await viewModel.loadSpeakerProfiles()
            }
            .onDisappear {
                viewModel.onDisappear()
                Task { await viewModel.cancelSpeakerEnrollment() }
            }
        }

        private struct TranscriptionModelRow: View {
            let name: String
            let isDownloaded: Bool
            let isDownloading: Bool
            let errorMessage: String?
            let onDownload: () -> Void
            let onReveal: () -> Void

            var body: some View {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(name)
                                .font(.system(size: 12, weight: .medium))
                            Text(isDownloaded ? "Downloaded" : "Available")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if isDownloading {
                            ProgressView()
                                .controlSize(.small)
                        }

                        HStack(spacing: 8) {
                            Button(action: onReveal) {
                                Image(systemName: "folder")
                                    .font(.system(size: 12))
                            }
                            .buttonStyle(.bordered)
                            .help("Reveal in Finder")

                            Button(isDownloaded ? "Downloaded" : "Download") {
                                onDownload()
                            }
                            .disabled(isDownloaded || isDownloading)
                        }
                    }

                    if let message = errorMessage {
                        Text(message)
                            .font(.system(size: 10))
                            .foregroundStyle(.red)
                    }
                }
            }
        }
    }
#endif
