#if os(macOS)
    import Foundation

    @testable import Stet

    @MainActor
    enum AppBranchTestSupport {
        struct Harness {
            let monitor: AppBranchMonitor
            let workspace: FakeAppBranchWorkspace
            func drainCallbacks() async {}
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
            let monitor = AppBranchMonitor(workspace: workspace)
            return Harness(monitor: monitor, workspace: workspace)
        }
    }

    @MainActor
    final class FakeAppBranchWorkspace: AppBranchWorkspaceObserving {
        private final class ObserverToken: NSObject {
            let id: UUID

            init(id: UUID) {
                self.id = id
            }
        }

        var frontmostApplication: AppBranchWorkspaceApplicationSnapshot?

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
            observers[observer.id] = handler
            observerCount += 1
            activeObserverCount = observers.count
            return token
        }

        func removeObservation(_ token: AppBranchWorkspaceObservationToken) {
            guard let observer = token.observer as? ObserverToken else { return }
            observers.removeValue(forKey: observer.id)
            removedObserverCount += 1
            activeObserverCount = observers.count
        }

        func simulateActivationChange() {
            let callbacks = Array(observers.values)

            for observer in callbacks {
                observer()
            }
        }
    }
#endif
