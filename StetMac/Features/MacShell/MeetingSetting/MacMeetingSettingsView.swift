#if os(macOS)
    import AppKit
    import SwiftUI

    struct MacMeetingSettingsView: View {
        @State private var recentFolders: [URL] = []
        @State private var revealMessage: String?

        private let store = MeetingRecordingStore()

        var body: some View {
            Form {
                Section {
                    MacHotKeySettingsSectionView(hotkey: .meeting)
                } header: {
                    Text("Shortcut")
                } footer: {
                    Text(
                        "Control-Option-Command-M is the default. The shortcut toggles recording on key down; it is not hold-to-talk."
                    )
                }

                Section {
                    LabeledContent("Location") {
                        Text(store.rootDirectory.path)
                            .textSelection(.enabled)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Button("Reveal Meetings Folder") {
                        revealMeetingsFolder()
                    }
                    if let revealMessage {
                        Text(revealMessage)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Meetings Folder")
                } footer: {
                    Text("Each recording is saved as a folder named with the local start time.")
                }

                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("yyyy-MM-dd HH-mm-ss/")
                        Text("  audio.wav")
                        Text("  transcript.md")
                        Text("  session.json")
                    }
                    .font(.system(.body, design: .monospaced))

                    Text(
                        "Speaker labels are Me when your enrolled voice matches a track, Speaker 1–4 for other people, and Unresolved when people talk over each other. Meetings are not rewritten, pasted, or added to History."
                    )
                    .foregroundStyle(.secondary)
                } header: {
                    Text("What's in a meeting folder")
                }

                if !recentFolders.isEmpty {
                    Section {
                        ForEach(recentFolders, id: \.path) { url in
                            Button(url.lastPathComponent) {
                                NSWorkspace.shared.activateFileViewerSelecting([url])
                            }
                        }
                    } header: {
                        Text("Recent")
                    }
                }
            }
            .formStyle(.grouped)
            .padding(.leading, MacUI.SettingsViewMetrics.formHorizontalPadding)
            .padding(.bottom, MacUI.SettingsViewMetrics.formBottomPadding)
            .task {
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
