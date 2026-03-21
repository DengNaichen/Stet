#if os(macOS)
import Foundation
import SwiftUI

struct MacMenuBarView: View {
    @EnvironmentObject private var settingsShellViewModel: MacSettingsShellViewModel
    @EnvironmentObject private var appUpdateManager: AppUpdateManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            AudioInputDeviceMenuSection()
            
            Divider()
            
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
        .task {
            AudioDeviceSelectionManager.shared.refreshDevices()
            AudioDeviceChangeMonitor.shared.startMonitoring()
            
            if #available(macOS 15.0, *) {
                let shader = ShaderLibrary.cloudOrbGlassWide(
                    .float2(CGSize(width: 250, height: 52)),
                    .float(0),
                    .float(0.1),
                    .color(.white),
                    .color(.white),
                    .color(.white)
                )
                try? await shader.compile(as: .colorEffect)
            }
        }
        .onDisappear {
            AudioDeviceChangeMonitor.shared.stopMonitoring()
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
