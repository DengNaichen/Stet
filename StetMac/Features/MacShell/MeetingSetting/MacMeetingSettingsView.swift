#if os(macOS)
    import AppKit
    import SwiftUI

    struct MacMeetingSettingsView: View {
        @Environment(MacMeetingViewModel.self) private var meetingViewModel
        @State private var recentFolders: [URL] = []
        @State private var revealMessage: String?

        private let store = MeetingRecordingStore()

        var body: some View {
            LinearPageContainer(title: "Meetings") {
                MacCalendarMeetingSettingsView(appModel: meetingViewModel)

                LinearSectionGroup(
                    "Recording",
                    footer:
                        "Records your selected microphone and system audio, including calls played through headphones."
                ) {
                    LinearSettingRow(
                        LocalizedStringKey(meetingViewModel.meetingToggleTitle),
                        subtitleText: meetingViewModel.meetingStatusText
                    ) {
                        Button {
                            meetingViewModel.toggleMeetingRecording()
                        } label: {
                            Label(
                                LocalizedStringKey(meetingViewModel.meetingToggleTitle),
                                systemImage: meetingViewModel.meetingMenuSymbolName
                            )
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!meetingViewModel.canToggleMeetingRecording)
                    }
                }

                MeetingSpeakerSettingsSection(
                    settings: meetingViewModel.meetingSpeakerSettings,
                    isRecording: meetingViewModel.isMeetingBusy
                )

                LinearSectionGroup(
                    "Shortcut",
                    footer: "Toggles recording. It is not hold-to-talk."
                ) {
                    MacHotKeySettingsSectionView(hotkey: .meeting, compactRow: true)
                }

                LinearSectionGroup("Recordings") {
                    LinearSettingRow("Meetings Folder") {
                        Button("Reveal Meetings Folder") {
                            revealMeetingsFolder()
                        }
                        .buttonStyle(.bordered)
                    }

                    if let revealMessage {
                        Text(revealMessage)
                            .font(MacUI.LinearTypography.rowSubtitle)
                            .foregroundStyle(MacUI.Foreground.error)
                            .padding(.horizontal, MacUI.LinearMetrics.rowHorizontalPadding)
                            .padding(.vertical, 6)
                    }
                }

                if !recentFolders.isEmpty {
                    LinearSectionGroup("Recent") {
                        ForEach(recentFolders, id: \.path) { url in
                            LinearSettingRow(LocalizedStringKey(url.lastPathComponent)) {
                                Button("Show in Finder") {
                                    NSWorkspace.shared.activateFileViewerSelecting([url])
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }
            }
            .task {
                reloadRecentFolders()
            }
            .onChange(of: meetingViewModel.meetingRecordingPhase) { _, _ in
                reloadRecentFolders()
            }
        }

        private func revealMeetingsFolder() {
            do {
                let url = try store.ensureRootDirectory()
                NSWorkspace.shared.activateFileViewerSelecting([url])
                revealMessage = nil
            } catch {
                revealMessage = error.localizedDescription
            }
        }

        private func reloadRecentFolders() {
            recentFolders = (try? store.recentSessionDirectories(limit: 8)) ?? []
        }
    }
#endif
