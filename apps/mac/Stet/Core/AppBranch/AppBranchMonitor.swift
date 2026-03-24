import AppKit
import Foundation

private extension NSLocking {
    nonisolated func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}

private nonisolated struct AppBranchMonitorState {
    var isMonitoring = false
    var excludedBundleID: String?
    var currentNonExcludedApp: AppInfo?
    var previousNonExcludedApp: AppInfo?
    var observationToken: AppBranchWorkspaceObservationToken?
    var observers: [UUID: AppChangeObserver] = [:]
}

/// Detects the current frontmost app and publishes activation changes.
///
/// The monitor keeps the public API small, but its internal dependencies are
/// injectable so tests can swap in a fake workspace and deterministic snapshot.
public nonisolated final class AppBranchMonitor: @unchecked Sendable {
    public nonisolated static let shared = AppBranchMonitor()

    private let workspace: any AppBranchWorkspaceObserving
    private let callbackQueue: DispatchQueue
    private let stateLock = NSRecursiveLock()
    private var state = AppBranchMonitorState()

    nonisolated init(
        workspace: any AppBranchWorkspaceObserving = LiveAppBranchWorkspace(),
        callbackQueue: DispatchQueue = DispatchQueue(
            label: "com.stet.appbranch.callbacks",
            qos: .userInitiated
        )
    ) {
        self.workspace = workspace
        self.callbackQueue = callbackQueue
    }

    deinit {
        stopMonitoring()
    }

    /// The currently active foreground application.
    ///
    /// This is computed on demand from the live workspace snapshot and the
    /// monitor's exclusion state.
    public nonisolated var currentApp: AppInfo? {
        let frontmostApp = workspace.frontmostApplication
        return stateLock.withLock {
            resolveCurrentApp(from: frontmostApp)
        }
    }

    public nonisolated var isMonitoring: Bool {
        stateLock.withLock {
            state.isMonitoring
        }
    }

    public nonisolated var excludedBundleID: String? {
        get {
            stateLock.withLock {
                state.excludedBundleID
            }
        }
        set {
            stateLock.withLock {
                state.excludedBundleID = newValue
            }
        }
    }

    public nonisolated func startMonitoring() {
        let token = workspace.observeFrontmostApplicationChanges { [weak self] in
            self?.scheduleWorkspaceRefresh()
        }

        let shouldScheduleInitialRefresh = stateLock.withLock {
            guard !state.isMonitoring else {
                return false
            }

            state.isMonitoring = true
            state.observationToken = token
            return true
        }

        guard shouldScheduleInitialRefresh else {
            workspace.removeObservation(token)
            return
        }

        scheduleWorkspaceRefresh()
    }

    public nonisolated func stopMonitoring() {
        let token: AppBranchWorkspaceObservationToken? = stateLock.withLock {
            guard state.isMonitoring else {
                return nil
            }

            state.isMonitoring = false
            let token = state.observationToken
            state.observationToken = nil
            return token
        }

        guard let token else { return }
        workspace.removeObservation(token)
    }

    public nonisolated func addObserver(_ callback: @escaping AppChangeCallback) -> UUID {
        stateLock.withLock {
            let observerID = UUID()
            state.observers[observerID] = AppChangeObserver(
                id: observerID,
                callback: callback,
                createdAt: Date()
            )
            return observerID
        }
    }

    public nonisolated func removeObserver(_ id: UUID) {
        stateLock.withLock {
            _ = state.observers.removeValue(forKey: id)
        }
    }

    public nonisolated func setExcludedBundleID(_ bundleID: String?) {
        stateLock.withLock {
            state.excludedBundleID = bundleID
        }
    }

    private nonisolated func scheduleWorkspaceRefresh() {
        callbackQueue.async { [weak self] in
            self?.refreshAndNotifyObservers()
        }
    }

    private nonisolated func refreshAndNotifyObservers() {
        let snapshot: (AppInfo?, [AppChangeCallback])? = stateLock.withLock {
            guard state.isMonitoring else {
                return nil
            }

            let appInfo = resolveCurrentApp(from: workspace.frontmostApplication)
            let callbacks = state.observers.values.map(\.callback)
            return (appInfo, callbacks)
        }

        guard let snapshot else { return }

        for callback in snapshot.1 {
            callback(snapshot.0)
        }
    }

    private nonisolated func resolveCurrentApp(
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
