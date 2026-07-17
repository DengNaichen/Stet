#if os(macOS)
    import AppKit
    import Foundation
    import SwiftUI

    @MainActor
    final class MacShellPresentationController: MacShellPresenting {
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
            self.panelController.onHide = { [weak self] in
                self?.panelDidHide()
            }
        }

        func showPanel(appModel: any MacDictationPanelCoordinating) {
            showPanel(appModel: appModel, mode: .manual)
        }

        func showTransientPanel(appModel: any MacDictationPanelCoordinating) {
            showPanel(appModel: appModel, mode: .transient)
        }

        func hidePanel() {
            cancelScheduledPanelHide()
            panelController.hide()
            isPanelVisible = false
            panelPresentationMode = .manual
        }

        func togglePanel(appModel: any MacDictationPanelCoordinating) {
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
                try? await Task.sleep(for: .milliseconds(50))
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
            appModel: any MacDictationPanelCoordinating,
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
#endif
