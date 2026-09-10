#if os(macOS)
    import SwiftUI
    import StetCore

    struct MacVoiceSettingsView: View {
        @StateObject private var viewModel = MacAudioSettingsViewModel()

        var body: some View {
            Form {
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
            .macSettingsFormStyle()
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
    }
#endif
