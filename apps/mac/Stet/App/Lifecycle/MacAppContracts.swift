#if os(macOS)
import Combine
import Foundation

@MainActor
protocol MacAppStatusObserving: AnyObject {
    var updates: AnyPublisher<Void, Never> { get }
}

@MainActor
protocol MacDictationCommandsCoordinating: MacAppStatusObserving {
    var menuBarSymbolName: String { get }
    var primaryButtonTitle: String { get }
    var panelButtonTitle: String { get }
    func performPrimaryAction()
    func togglePanel()
}

@MainActor
protocol MacDictationPanelCoordinating: MacAppStatusObserving {
    var dictationState: DictationState { get }
    var statusText: String { get }
    var recordingLevel: Double { get }
    func hidePanel()
    func dismissPendingCopy()
    func cancelActiveCapture()
    func performPrimaryAction()
}

@MainActor
protocol MacPermissionsCoordinating: MacAppStatusObserving {
    var autoPasteStatusText: String { get }
    var microphoneAccessStatusText: String { get }
    var microphoneAccessNeedsAttention: Bool { get }
    var microphonePermissionActionTitle: String { get }
    var autoPasteAccessNeedsAttention: Bool { get }
    func requestAutoPasteAccess()
    func resolveMicrophoneAccess()
    func openAccessibilitySettings()
}

@MainActor
protocol MacSettingsShellCoordinating: AnyObject, MacGeneralSettingsAppModeling {
    func openSettings(using action: () -> Void)
    func settingsDidAppear()
    func settingsDidDisappear()
}

@MainActor
protocol MacAppPresentationModeling: MacDictationPanelCoordinating, MacPermissionsCoordinating {}

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
    func registerDictationKeyUp(_ handler: @escaping () -> Void)
}
#endif
