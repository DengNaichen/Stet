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

            Button(appUpdateMenuTitle) {
                appUpdateManager.checkForUpdates()
            }
            .disabled(appUpdateManager.isChecking || !appUpdateManager.canCheckForUpdates)

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
    }

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
}
#endif

