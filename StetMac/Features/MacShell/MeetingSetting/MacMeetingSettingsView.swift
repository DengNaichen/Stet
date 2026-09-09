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
                    Text("Toggles recording. It is not hold-to-talk.")
                }

                Section {
                    Button("Reveal Meetings Folder") {
                        revealMeetingsFolder()
                    }
                    if let revealMessage {
                        Text(revealMessage)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Recordings")
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
