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

                #if !APP_STORE
                    Button(appUpdateMenuTitle) {
                        appUpdateManager.checkForUpdates()
                    }
                    .disabled(appUpdateManager.isChecking || !appUpdateManager.canCheckForUpdates)
                #endif

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

        #if !APP_STORE
            private var appUpdateMenuTitle: String {
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
        #endif
    }
#endif
