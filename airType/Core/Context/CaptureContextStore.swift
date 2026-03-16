#if os(macOS)
import Foundation

actor CaptureContextStore {
    private var currentContext = AppBranchContext(bundleID: nil, appName: nil, browserURL: nil)

    func updateApplication(bundleID: String?, appName: String?) {
        currentContext.bundleID = bundleID
        currentContext.appName = appName
        currentContext.browserURL = nil
    }

    func updateBrowserURL(_ url: String?) {
        currentContext.browserURL = url
    }

    func setContext(_ context: AppBranchContext) {
        currentContext = context
    }

    func context() -> AppBranchContext {
        currentContext
    }

    func snapshot() -> AppBranchContextSnapshot {
        AppBranchContextSnapshot(context: currentContext, capturedAt: .now)
    }
}
#endif
