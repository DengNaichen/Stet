#if os(macOS)
    import AppKit
    import Combine
    import Foundation
    import os

    extension MacAppSessionController {
        func activate(presentationModel: any MacAppPresentationModeling, showInDock: Bool) {
            self.presentationModel = presentationModel
            applyDockVisibility(showInDock: showInDock)

            DispatchQueue.main.async { [weak self] in
                self?.resetOnboardingProgressIfNeeded()
                self?.refreshPermissionIndicators()
                self?.prewarmAudioEngine()
            }
        }

        func cancelActiveCapture() {
            hotkeyInteraction.reset()
            workflowController.cancelActiveCapture()
            hidePanel()
        }

        func requestAutoPasteAccess() {
            permissionManager.requestAutoPasteAccess()
            refreshPermissionIndicators()
        }

        func resolveMicrophoneAccess() {
            if permissionManager.microphoneAccessStatus.canRequestInApp {
                requestMicrophoneAccess()
            } else {
                openMicrophoneSettings()
            }
        }

        func openAccessibilitySettings() {
            permissionManager.openAccessibilitySettings()
        }

        func openMicrophoneSettings() {
            permissionManager.openMicrophoneSettings()
        }

        func showPanel() {
            guard !requiresOnboarding || onboardingStepState.allowsAudioCapture else {
                presentRequiredPermissionsGateIfNeeded()
                return
            }

            guard hasRequiredPermissions else {
                presentRequiredPermissionsGateIfNeeded()
                return
            }

            guard let presentationModel else { return }
            shellPresentationController.showPanel(appModel: presentationModel)
        }

        func hidePanel() {
            Task {
                await DictationRuntimeProbe.shared.markPanelHidden()
            }
            shellPresentationController.hidePanel()
        }

        func dismissPendingCopy() {
            Task {
                await DictationRuntimeProbe.shared.markPendingCopyDismissed()
            }
            guard case .clipboardPending = dictationState else {
                hidePanel()
                return
            }

            hidePanel()
            workflowController.dictationViewModel.send(.resetTapped)
        }

        func togglePanel() {
            guard !requiresOnboarding || onboardingStepState.allowsAudioCapture || isPanelVisible else {
                presentRequiredPermissionsGateIfNeeded()
                return
            }

            guard hasRequiredPermissions || isPanelVisible else {
                presentRequiredPermissionsGateIfNeeded()
                return
            }

            guard let presentationModel else { return }
            shellPresentationController.togglePanel(appModel: presentationModel)
        }

        func previewPermissionIndicators() {
            refreshPermissionIndicators()
        }

        func applyDockVisibility(showInDock: Bool) {
            shellPresentationController.applyDockVisibility(showInDock: showInDock)
        }

        func openSettings(using action: () -> Void) {
            shellPresentationController.openSettings(
                currentShowInDockPreference: currentShowInDockPreference,
                using: action
            )
        }

        func settingsDidAppear() {
            shellPresentationController.settingsDidAppear(
                currentShowInDockPreference: currentShowInDockPreference
            )
        }

        func settingsDidDisappear() {
            shellPresentationController.settingsDidDisappear(
                currentShowInDockPreference: currentShowInDockPreference
            )
        }

        func refreshRuntimeFromSettings() {
            applyDockVisibility(showInDock: currentShowInDockPreference)
            notifyChange()
        }
    }

    extension MacAppSessionController {
        func prewarmAudioEngine() {
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                // Add a one-second delay to avoid blocking UI during activation
                try? await Task.sleep(nanoseconds: 1_000_000_000)

                Self.logger.info("Pre-warming audio engine on activation after delay")
                await workflowController.prewarm()
            }
        }

        func configureAppBranchMonitoring() {
            guard appBranchObserverID == nil else { return }

            appBranchMonitor.setExcludedBundleID(Bundle.main.bundleIdentifier)
            detectedTargetApplicationState = appBranchMonitor.currentApp
            appBranchObserverID = appBranchMonitor.addObserver { [weak self] appInfo in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    detectedTargetApplicationState = appInfo
                    notifyChange()
                }
            }
            appBranchMonitor.startMonitoring()
        }

        func bindLifecycleNotifications() {
            notificationCenter.publisher(for: NSApplication.willResignActiveNotification)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.handleAppLifecycleChange(to: "inactive")
                }
                .store(in: &cancellables)

            notificationCenter.publisher(for: NSApplication.didBecomeActiveNotification)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.refreshPermissionIndicators()
                    self?.handleAppLifecycleChange(to: "active")
                }
                .store(in: &cancellables)
        }

        func refreshPermissionIndicators() {
            resetOnboardingProgressIfNeeded()

            if shouldPresentPermissionGate {
                if !requiresOnboarding {
                    onboardingStepState = .permissions
                }
            } else {
                permissionGateController.hide()
            }

            notifyChange()
        }

        func requestMicrophoneAccess() {
            Task { @MainActor [weak self] in
                guard let self else { return }

                Self.permissionsLogger.info("Requesting microphone access from permissions gate")
                _ = await permissionManager.requestMicrophonePermission()
                refreshPermissionIndicators()
            }
        }

        func handleAppLifecycleChange(to newState: String) {
            let from = appLifecycleState
            guard from != newState else { return }
            appLifecycleState = newState

            Task {
                await DictationRuntimeProbe.shared.markAppStateChange(from: from, to: newState)
            }
        }

        func notifyChange() {
            syncOnboardingPresentation()
            onChange?()
        }

        func presentRequiredPermissionsGateIfNeeded() {
            if shouldPresentOnboardingGate {
                syncOnboardingPresentation()
                return
            }

            guard shouldPresentPermissionGate else {
                permissionGateController.hide()
                return
            }

            guard dictationState == .idle else {
                return
            }

            if isPanelVisible {
                shellPresentationController.hidePanel()
            }

            guard let presentationModel else { return }
            permissionGateController.show(appModel: presentationModel)
        }

        func syncOnboardingPresentation() {
            guard let presentationModel else {
                return
            }

            if requiresOnboarding, onboardingStepState != .done {
                onboardingWindowController.show(appModel: presentationModel)
            } else {
                onboardingWindowController.hide()
            }
        }
    }
#endif
