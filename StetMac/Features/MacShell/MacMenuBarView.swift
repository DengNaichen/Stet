#if os(macOS)
    import Foundation
    import SwiftUI

    struct MacMenuBarView: View {
        @EnvironmentObject private var meetingViewModel: MacMeetingViewModel
        @EnvironmentObject private var settingsShellViewModel: MacSettingsShellViewModel
        @EnvironmentObject private var appUpdateViewModel: MacAppUpdateViewModel
        @Environment(\.openWindow) private var openWindow
        @StateObject private var deviceList = AudioInputDeviceListViewModel()

        var body: some View {
            Group {
                Button {
                    meetingViewModel.toggleMeetingRecording()
                } label: {
                    Label(
                        meetingViewModel.meetingToggleTitle,
                        systemImage: meetingViewModel.meetingMenuSymbolName
                    )
                }
                .disabled(!meetingViewModel.canToggleMeetingRecording)

                if meetingViewModel.isMeetingBusy {
                    Text(meetingViewModel.meetingStatusText)
                        .foregroundStyle(.secondary)
                }

                Divider()

                Button("Settings…") {
                    settingsShellViewModel.openSettings {
                        openWindow(id: MacWindowSceneID.preferences)
                        NotificationCenter.default.post(name: .stetOpenSettings, object: nil)
                    }
                }

                Divider()

                Menu("Select Microphone") {
                    AudioInputDeviceMenuSection(deviceList: deviceList)
                }

                Button(appUpdateMenuTitle) {
                    appUpdateViewModel.checkForUpdates()
                }
                .disabled(appUpdateViewModel.isChecking || !appUpdateViewModel.canCheckForUpdates)

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .task {
                deviceList.startMonitoring()

                await MacDictationVisualsRuntime.prewarmIfAvailable()
            }
            .onDisappear {
                deviceList.stopMonitoring()
            }
        }

        private var appUpdateMenuTitle: LocalizedStringKey {
            switch appUpdateViewModel.state {
            case .updateAvailable(_, let latestVersion):
                return "Update Available (\(latestVersion))"
            case .checking:
                return "Checking for Updates…"
            case .unavailable:
                return "Updates Unavailable"
            default:
                return "Check for Updates…"
            }
        }
    }
#endif
