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
        private final class ObserverToken: NSObject {
            let id: UUID

            init(id: UUID) {
                self.id = id
            }
        }

        var frontmostApplication: AppBranchWorkspaceApplicationSnapshot?
        private let lock = NSLock()

        private var observers: [UUID: () -> Void] = [:]

        private(set) var observerCount = 0
        private(set) var activeObserverCount = 0
        private(set) var removedObserverCount = 0

        init(frontmostApplication: AppBranchWorkspaceApplicationSnapshot?) {
            self.frontmostApplication = frontmostApplication
        }

        func observeFrontmostApplicationChanges(_ handler: @escaping () -> Void) -> AppBranchWorkspaceObservationToken {
            let observer = ObserverToken(id: UUID())
            let token = AppBranchWorkspaceObservationToken(observer: observer)
            lock.lock()
            observers[observer.id] = handler
            observerCount += 1
            activeObserverCount = observers.count
            lock.unlock()
            return token
        }

        func removeObservation(_ token: AppBranchWorkspaceObservationToken) {
            guard let observer = token.observer as? ObserverToken else { return }
            lock.lock()
            observers.removeValue(forKey: observer.id)
            removedObserverCount += 1
            activeObserverCount = observers.count
            lock.unlock()
        }

        func simulateActivationChange() {
            lock.lock()
            let callbacks = Array(observers.values)
            lock.unlock()

            for observer in callbacks {
                observer()
            }
        }
    }
#endif
