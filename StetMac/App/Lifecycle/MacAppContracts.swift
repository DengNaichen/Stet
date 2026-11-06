#if os(macOS)
    import Combine
    import Foundation
    import StetVisuals

    @MainActor
    protocol MacShellPresenting: AnyObject {
        var onVisibilityChange: (() -> Void)? { get set }
        var isPanelVisible: Bool { get }
        func showPanel(appModel: any MacDictationPanelCoordinating)
        func showTransientPanel(appModel: any MacDictationPanelCoordinating)
        func hidePanel()
        func togglePanel(appModel: any MacDictationPanelCoordinating)
        func panelDidHide()
        func cancelScheduledPanelHide()
        func scheduleTransientPanelHideIfNeeded(currentState: @escaping @MainActor () -> DictationState)
        func applyDockVisibility(showInDock: Bool)
        func openSettings(currentShowInDockPreference: Bool, using action: () -> Void)
        func settingsDidAppear(currentShowInDockPreference: Bool)
        func settingsDidDisappear(currentShowInDockPreference: Bool)
    }

    @MainActor
    protocol MacPermissionGatePresenting: AnyObject {
        func show(appModel: any MacPermissionsCoordinating)
        func hide()
    }

    @MainActor
    protocol MacDictationHotkeyRegistering {
        func clearDictationHandlers()
        func registerDictationKeyDown(_ handler: @escaping () -> Void)
        func clearMeetingHandlers()
        func registerMeetingKeyDown(_ handler: @escaping () -> Void)
    }

    extension MacDictationHotkeyRegistering {
        func clearMeetingHandlers() {}
        func registerMeetingKeyDown(_ handler: @escaping () -> Void) {}
    }
#endif

extension Notification.Name {
    static let stetBillingCompleted = Notification.Name("stetBillingCompleted")
}
