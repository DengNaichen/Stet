#if os(macOS)
    import Foundation

    @testable import Stet

    enum AppBranchTestSupport {
        struct Harness {
            let monitor: AppBranchMonitor
            let workspace: FakeAppBranchWorkspace
            let callbackQueue: DispatchQueue

            func drainCallbacks() async {
                await withCheckedContinuation { continuation in
                    callbackQueue.async {
                        continuation.resume()
                    }
                }
            }
        }

        static func makeHarness(
            frontmostApplication: AppBranchWorkspaceApplicationSnapshot? = .init(
                bundleIdentifier: "com.apple.TextEdit",
                localizedName: "TextEdit",
                processIdentifier: 101,
                runningApplication: nil
            )
        ) -> Harness {
            let workspace = FakeAppBranchWorkspace(frontmostApplication: frontmostApplication)
            let callbackQueue = DispatchQueue(label: "com.stet.tests.appbranch.callbacks")
            let monitor = AppBranchMonitor(workspace: workspace, callbackQueue: callbackQueue)
            return Harness(monitor: monitor, workspace: workspace, callbackQueue: callbackQueue)
        }
    }

    final class FakeAppBranchWorkspace: AppBranchWorkspaceObserving {
        var frontmostApplication: AppBranchWorkspaceApplicationSnapshot?

        private var observers: [ObjectIdentifier: () -> Void] = [:]

        private(set) var observerCount = 0
        private(set) var activeObserverCount = 0
        private(set) var removedObserverCount = 0

        init(frontmostApplication: AppBranchWorkspaceApplicationSnapshot?) {
            self.frontmostApplication = frontmostApplication
        }

        func observeFrontmostApplicationChanges(_ handler: @escaping () -> Void) -> AppBranchWorkspaceObservationToken {
            let observer = NSObject()
            let token = AppBranchWorkspaceObservationToken(observer: observer)
            observers[ObjectIdentifier(observer)] = handler
            observerCount += 1
            activeObserverCount = observers.count
            return token
        }

        func removeObservation(_ token: AppBranchWorkspaceObservationToken) {
            observers.removeValue(forKey: ObjectIdentifier(token.observer))
            removedObserverCount += 1
            activeObserverCount = observers.count
        }

        func simulateActivationChange() {
            for observer in observers.values {
                observer()
            }
        }
    }
#endif
