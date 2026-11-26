#if os(macOS)
    import AppKit
    import KeyboardShortcuts
    import SwiftUI

    struct MacMeetingSettingsView: View {
        @Environment(MacMeetingViewModel.self) private var meetingViewModel
        var onOpenShortcutSettings: (() -> Void)? = nil

        @State private var recentFolders: [URL] = []
        @State private var revealMessage: String?
        @State private var meetingShortcutDisplay: String?

        private let store = MeetingRecordingStore()

        var body: some View {
            LinearPageContainer(title: "Meetings") {
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

                    LinearSettingRow(
                        "Shortcut",
                        subtitle: "Toggles meeting recording. Managed in Settings → Dictation."
                    ) {
                        HStack(spacing: 8) {
                            if let meetingShortcutDisplay {
                                LinearKbdHint(text: meetingShortcutDisplay)
                            } else {
                                Text("Not set")
                                    .font(MacUI.LinearTypography.rowSubtitle)
                                    .foregroundStyle(MacUI.Foreground.secondary)
                            }

                            if let onOpenShortcutSettings {
                                Button("Change Shortcut…", action: onOpenShortcutSettings)
                                    .buttonStyle(.bordered)
                            }
                        }
                    }
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
                            LinearSettingRow(titleText: url.lastPathComponent) {
                                Button("Show in Finder") {
                                    NSWorkspace.shared.activateFileViewerSelecting([url])
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }

                MacCalendarMeetingSettingsView(appModel: meetingViewModel)

                MeetingSpeakerSettingsSection(
                    settings: meetingViewModel.meetingSpeakerSettings,
                    isRecording: meetingViewModel.isMeetingBusy
                )
            }
            .task {
                reloadRecentFolders()
                reloadMeetingShortcut()
            }
            .onAppear {
                reloadMeetingShortcut()
            }
            .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
                reloadMeetingShortcut()
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

        private func reloadMeetingShortcut() {
            meetingShortcutDisplay = KeyboardShortcuts.getShortcut(for: HotkeyBinding.meeting.name).map { "\($0)" }
        }
    }
#endif
