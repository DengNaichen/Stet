import AppKit
import Foundation

struct AppBranchWorkspaceApplicationSnapshot {
    let bundleIdentifier: String?
    let localizedName: String?
    let processIdentifier: pid_t
    let runningApplication: NSRunningApplication?

    init(
        bundleIdentifier: String?,
        localizedName: String?,
        processIdentifier: pid_t,
        runningApplication: NSRunningApplication?
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.localizedName = localizedName
        self.processIdentifier = processIdentifier
        self.runningApplication = runningApplication
    }

    init(runningApplication: NSRunningApplication) {
        self.init(
            bundleIdentifier: runningApplication.bundleIdentifier,
            localizedName: runningApplication.localizedName,
            processIdentifier: runningApplication.processIdentifier,
            runningApplication: runningApplication
        )
    }
}

/// Abstraction over the workspace APIs AppBranch uses.
///
/// This keeps the monitor deterministic in tests by allowing the frontmost app
/// snapshot and activation observation to be supplied by a fake workspace.
protocol AppBranchWorkspaceObserving {
    var frontmostApplication: AppBranchWorkspaceApplicationSnapshot? { get }

    func observeFrontmostApplicationChanges(_ handler: @escaping () -> Void) -> AppBranchWorkspaceObservationToken
    func removeObservation(_ token: AppBranchWorkspaceObservationToken)
}

/// Lightweight wrapper around a notification observer token.
///
/// The monitor owns this token and hands it back to the workspace for cleanup.
final class AppBranchWorkspaceObservationToken {
    let observer: NSObjectProtocol

    init(observer: NSObjectProtocol) {
        self.observer = observer
    }
}

/// Live `NSWorkspace` implementation used by the app at runtime.
final class LiveAppBranchWorkspace: AppBranchWorkspaceObserving {
    private let workspace: NSWorkspace

    init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
    }

    var frontmostApplication: AppBranchWorkspaceApplicationSnapshot? {
        guard let runningApplication = workspace.frontmostApplication else {
            return nil
        }

        return AppBranchWorkspaceApplicationSnapshot(runningApplication: runningApplication)
    }

    func observeFrontmostApplicationChanges(_ handler: @escaping () -> Void) -> AppBranchWorkspaceObservationToken {
        let observer = workspace.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: nil
        ) { _ in
            handler()
        }

        return AppBranchWorkspaceObservationToken(observer: observer)
    }

    func removeObservation(_ token: AppBranchWorkspaceObservationToken) {
        workspace.notificationCenter.removeObserver(token.observer)
    }
}
