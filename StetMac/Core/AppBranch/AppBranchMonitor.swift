import AppKit
import Foundation

private struct AppBranchMonitorState {
    var isMonitoring = false
    var excludedBundleID: String?
    var currentNonExcludedApp: AppInfo?
    var previousNonExcludedApp: AppInfo?
    var observationToken: AppBranchWorkspaceObservationToken?
    var observers: [UUID: AppChangeObserver] = [:]
}

/// Owns workspace observation and publishes snapshots on the main actor.
@MainActor
public final class AppBranchMonitor {
    public static let shared = AppBranchMonitor()

    private let workspace: any AppBranchWorkspaceObserving
    private var state = AppBranchMonitorState()

    init(workspace: (any AppBranchWorkspaceObserving)? = nil) {
        self.workspace = workspace ?? LiveAppBranchWorkspace()
    }

    isolated deinit {
        stopMonitoring()
    }

    public var currentApp: AppInfo? {
        resolveCurrentApp(from: workspace.frontmostApplication)
    }

    public var isMonitoring: Bool { state.isMonitoring }

    public var excludedBundleID: String? {
        get { state.excludedBundleID }
        set { state.excludedBundleID = newValue }
    }

    public func startMonitoring() {
        guard !state.isMonitoring else { return }
        state.isMonitoring = true
        state.observationToken = workspace.observeFrontmostApplicationChanges { [weak self] in
            self?.refreshAndNotifyObservers()
        }
        refreshAndNotifyObservers()
    }

    public func stopMonitoring() {
        guard state.isMonitoring else { return }
        state.isMonitoring = false
        if let token = state.observationToken {
            workspace.removeObservation(token)
        }
        state.observationToken = nil
    }

    public func addObserver(_ callback: @escaping AppChangeCallback) -> UUID {
        let id = UUID()
        state.observers[id] = AppChangeObserver(id: id, callback: callback, createdAt: Date())
        return id
    }

    public func removeObserver(_ id: UUID) {
        state.observers.removeValue(forKey: id)
    }

    public func setExcludedBundleID(_ bundleID: String?) {
        state.excludedBundleID = bundleID
    }

    private func refreshAndNotifyObservers() {
        guard state.isMonitoring else { return }
        let appInfo = currentApp
        let callbacks = Array(state.observers.values.map(\.callback))
        for callback in callbacks {
            callback(appInfo)
        }
    }

    private func resolveCurrentApp(
        from frontmostApp: AppBranchWorkspaceApplicationSnapshot?
    ) -> AppInfo? {
        guard let frontmostApp else {
            NSLog("[AppBranchMonitor] Warning: No frontmost application available.")
            return nil
        }

        guard let bundleID = frontmostApp.bundleIdentifier else {
            NSLog("[AppBranchMonitor] Warning: Frontmost application has no bundle identifier.")
            return nil
        }

        if let excludedID = state.excludedBundleID, bundleID == excludedID {
            if let currentNonExcludedApp = state.currentNonExcludedApp,
                currentNonExcludedApp.bundleIdentifier != excludedID
            {
                return currentNonExcludedApp
            }

            if let previousNonExcludedApp = state.previousNonExcludedApp,
                previousNonExcludedApp.bundleIdentifier != excludedID
            {
                return previousNonExcludedApp
            }
            return nil
        }

        let appInfo = AppInfo(
            bundleIdentifier: bundleID,
            localizedName: frontmostApp.localizedName ?? bundleID,
            processIdentifier: frontmostApp.processIdentifier,
            isOwnHostApplication: bundleID == Bundle.main.bundleIdentifier,
            runningApplication: frontmostApp.runningApplication
        )

        if state.currentNonExcludedApp?.bundleIdentifier != appInfo.bundleIdentifier {
            state.previousNonExcludedApp = state.currentNonExcludedApp
        }
        state.currentNonExcludedApp = appInfo
        return appInfo
    }
}
