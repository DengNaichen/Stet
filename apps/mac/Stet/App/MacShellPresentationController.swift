#if os(macOS)
import AppKit
import Foundation
import SwiftUI

@MainActor
final class MacShellPresentationController {
    private enum PanelPresentationMode {
        case manual
        case transient
    }

    private let panelController: MacPanelController
    var onVisibilityChange: (() -> Void)?

    private(set) var isPanelVisible = false {
        didSet {
            guard oldValue != isPanelVisible else { return }
            onVisibilityChange?()
        }
    }

    private var panelHideTask: Task<Void, Never>?
    private var panelPresentationMode: PanelPresentationMode = .manual
    private var isSettingsVisible = false
    private var shouldRestoreAccessoryModeAfterSettings = false

    init() {
        self.panelController = MacPanelController()
    }

    func showPanel(appModel: MacAppModel) {
        showPanel(appModel: appModel, mode: .manual)
    }

    func showTransientPanel(appModel: MacAppModel) {
        showPanel(appModel: appModel, mode: .transient)
    }

    func hidePanel() {
        cancelScheduledPanelHide()
        panelController.hide()
        isPanelVisible = false
        panelPresentationMode = .manual
    }

    func togglePanel(appModel: MacAppModel) {
        if isPanelVisible {
            hidePanel()
        } else {
            showPanel(appModel: appModel)
        }
    }

    func panelDidHide() {
        isPanelVisible = false
        panelPresentationMode = .manual
    }

    func cancelScheduledPanelHide() {
        panelHideTask?.cancel()
        panelHideTask = nil
    }

    func scheduleTransientPanelHideIfNeeded(currentState: @escaping @MainActor () -> DictationState) {
        guard panelPresentationMode == .transient, isPanelVisible else { return }

        panelHideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard let self else { return }
            guard case .idle = currentState() else { return }
            guard panelPresentationMode == .transient else { return }
            hidePanel()
        }
    }

    func applyDockVisibility(showInDock: Bool) {
        if showInDock {
            shouldRestoreAccessoryModeAfterSettings = false
            MacAppBehaviorController.applyDockVisibility(showInDock: true)
            return
        }

        if isSettingsVisible {
            shouldRestoreAccessoryModeAfterSettings = true
            MacAppBehaviorController.applyDockVisibility(showInDock: true)
            return
        }

        shouldRestoreAccessoryModeAfterSettings = false
        MacAppBehaviorController.applyDockVisibility(showInDock: false)
    }

    func openSettings(
        currentShowInDockPreference: Bool,
        using action: () -> Void
    ) {
        prepareForSettingsPresentation(currentShowInDockPreference: currentShowInDockPreference)
        action()
    }

    func settingsDidAppear(currentShowInDockPreference: Bool) {
        isSettingsVisible = true
        prepareForSettingsPresentation(currentShowInDockPreference: currentShowInDockPreference)
    }

    func settingsDidDisappear(currentShowInDockPreference: Bool) {
        isSettingsVisible = false
        applyDockVisibility(showInDock: currentShowInDockPreference)
    }

    private func showPanel(
        appModel: MacAppModel,
        mode: PanelPresentationMode
    ) {
        cancelScheduledPanelHide()
        panelPresentationMode = mode
        panelController.show(
            appModel: appModel,
            mode: mode == .manual ? .manual : .transient
        )
        isPanelVisible = true
    }

    private func prepareForSettingsPresentation(currentShowInDockPreference: Bool) {
        if !currentShowInDockPreference {
            shouldRestoreAccessoryModeAfterSettings = true
        }

        MacAppBehaviorController.applyDockVisibility(showInDock: true)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
final class MacPermissionGateController: NSObject, NSWindowDelegate {
    private final class PermissionsPanel: NSPanel {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { true }
    }

    private var panel: NSPanel?

    func show(appModel: MacAppModel) {
        if panel == nil {
            panel = makePanel(appModel: appModel)
        }

        guard let panel else { return }

        panel.contentViewController = NSHostingController(
            rootView: MacRequiredPermissionsGateView()
                .environmentObject(appModel)
        )

        if !panel.isVisible {
            panel.center()
        }

        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide()
        return false
    }

    private func makePanel(appModel: MacAppModel) -> NSPanel {
        let panel = PermissionsPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 320),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.delegate = self
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .modalPanel
        panel.isReleasedWhenClosed = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.animationBehavior = .utilityWindow
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.contentViewController = NSHostingController(
            rootView: MacRequiredPermissionsGateView()
                .environmentObject(appModel)
        )

        return panel
    }
}
#endif
