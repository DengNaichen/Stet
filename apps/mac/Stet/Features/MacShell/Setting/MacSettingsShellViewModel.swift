#if os(macOS)
import Combine
import Foundation

@MainActor
final class MacSettingsShellViewModel: ObservableObject, MacGeneralSettingsAppModeling {
    private let coordinator: any MacSettingsShellCoordinating

    init(coordinator: any MacSettingsShellCoordinating) {
        self.coordinator = coordinator
    }

    func openSettings(using action: () -> Void) {
        coordinator.openSettings(using: action)
    }

    func settingsDidAppear() {
        coordinator.settingsDidAppear()
    }

    func settingsDidDisappear() {
        coordinator.settingsDidDisappear()
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) throws {
        try coordinator.setLaunchAtLoginEnabled(enabled)
    }

    func refreshRuntimeFromSettings() {
        coordinator.refreshRuntimeFromSettings()
    }

    func applyDockVisibility(showInDock: Bool) {
        coordinator.applyDockVisibility(showInDock: showInDock)
    }
}
#endif
