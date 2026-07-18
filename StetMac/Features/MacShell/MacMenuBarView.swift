#if os(macOS)
    import Foundation
    import SwiftUI

    struct MacMenuBarView: View {
        @EnvironmentObject private var settingsShellViewModel: MacSettingsShellViewModel
        @EnvironmentObject private var appUpdateManager: AppUpdateManager
        @Environment(\.openWindow) private var openWindow

        var body: some View {
            Group {
                Button("Settings…") {
                    settingsShellViewModel.openSettings {
                        openWindow(id: MacWindowSceneID.preferences)
                    }
                }

                Divider()

                Menu("Select Microphone") {
                    AudioInputDeviceMenuSection()
                }

                Button(appUpdateMenuTitle) {
                    appUpdateManager.checkForUpdates()
                }
                .disabled(appUpdateManager.isChecking || !appUpdateManager.canCheckForUpdates)

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .task {
                AudioDeviceSelectionManager.shared.refreshDevices()
                AudioDeviceChangeMonitor.shared.startMonitoring()

                await MacDictationVisualsRuntime.prewarmIfAvailable()
            }
            .onDisappear {
                AudioDeviceChangeMonitor.shared.stopMonitoring()
            }
        }

        private var appUpdateMenuTitle: LocalizedStringKey {
            switch appUpdateManager.state {
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
