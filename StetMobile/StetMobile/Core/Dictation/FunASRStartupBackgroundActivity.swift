import UIKit

@MainActor
protocol FunASRStartupBackgroundActivityManaging: AnyObject {
    func begin(expirationHandler: @escaping @MainActor @Sendable () -> Void)
    func end()
}

@MainActor
final class SystemFunASRStartupBackgroundActivityManager: FunASRStartupBackgroundActivityManaging {
    private var identifier: UIBackgroundTaskIdentifier = .invalid

    func begin(expirationHandler: @escaping @MainActor @Sendable () -> Void) {
        end()
        identifier = UIApplication.shared.beginBackgroundTask(
            withName: "FunASR Realtime startup"
        ) {
            Task { @MainActor in
                expirationHandler()
            }
        }
    }

    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}
