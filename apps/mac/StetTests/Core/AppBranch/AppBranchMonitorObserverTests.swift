#if os(macOS)
import Foundation
import Testing

@testable import Stet

extension AppBranchTests {
    @Test("addObserver returns valid UUID")
    func addObserverReturnsValidUUID() {
        let harness = AppBranchTestSupport.makeHarness()
        let observerID = harness.monitor.addObserver { _ in }

        #expect(!observerID.uuidString.isEmpty)

        harness.monitor.removeObserver(observerID)
    }

    @Test("removeObserver handles invalid UUID gracefully")
    func removeObserverHandlesInvalidUUIDGracefully() {
        let harness = AppBranchTestSupport.makeHarness()
        let invalidID = UUID()

        harness.monitor.removeObserver(invalidID)
        harness.monitor.removeObserver(invalidID)
    }

    @Test("removeObserver removes the correct observer")
    func removeObserverRemovesCorrectObserver() async {
        let harness = AppBranchTestSupport.makeHarness(
            frontmostApplication: .init(
                bundleIdentifier: "com.apple.Safari",
                localizedName: "Safari",
                processIdentifier: 42,
                runningApplication: nil
            )
        )
        let monitor = harness.monitor
        var observer1Called = false
        var observer2Called = false

        let observer1ID = monitor.addObserver { _ in
            observer1Called = true
        }

        let observer2ID = monitor.addObserver { _ in
            observer2Called = true
        }

        monitor.removeObserver(observer1ID)
        monitor.startMonitoring()
        await harness.drainCallbacks()

        #expect(!observer1Called)
        #expect(observer2Called)

        monitor.removeObserver(observer2ID)
        monitor.stopMonitoring()
        await harness.drainCallbacks()
    }

    @Test("multiple observers can be registered")
    func multipleObserversCanBeRegistered() {
        let harness = AppBranchTestSupport.makeHarness()
        let observer1ID = harness.monitor.addObserver { _ in }
        let observer2ID = harness.monitor.addObserver { _ in }
        let observer3ID = harness.monitor.addObserver { _ in }

        #expect(observer1ID != observer2ID)
        #expect(observer2ID != observer3ID)
        #expect(observer1ID != observer3ID)

        harness.monitor.removeObserver(observer1ID)
        harness.monitor.removeObserver(observer2ID)
        harness.monitor.removeObserver(observer3ID)
    }

    @Test("observer receives initial snapshot when monitoring starts")
    func observerReceivesInitialSnapshotWhenMonitoringStarts() async {
        let harness = AppBranchTestSupport.makeHarness(
            frontmostApplication: .init(
                bundleIdentifier: "com.apple.Notes",
                localizedName: "Notes",
                processIdentifier: 77,
                runningApplication: nil
            )
        )
        let monitor = harness.monitor

        await confirmation("initial snapshot", expectedCount: 1) { confirm in
            let observerID = monitor.addObserver { appInfo in
                if appInfo?.bundleIdentifier == "com.apple.Notes" {
                    confirm()
                }
            }

            monitor.startMonitoring()
            await harness.drainCallbacks()
            monitor.removeObserver(observerID)
        }

        monitor.stopMonitoring()
        await harness.drainCallbacks()
    }

    @Test("removeObserver prevents later callbacks")
    func removeObserverPreventsLaterCallbacks() async {
        let harness = AppBranchTestSupport.makeHarness(
            frontmostApplication: .init(
                bundleIdentifier: "com.apple.Notes",
                localizedName: "Notes",
                processIdentifier: 77,
                runningApplication: nil
            )
        )
        let monitor = harness.monitor
        var callbackCount = 0

        let observerID = monitor.addObserver { _ in
            callbackCount += 1
        }

        monitor.removeObserver(observerID)
        monitor.startMonitoring()
        await harness.drainCallbacks()

        #expect(callbackCount == 0)

        monitor.stopMonitoring()
        await harness.drainCallbacks()
    }

    @Test("observer receives updates when workspace changes")
    func observerReceivesUpdatesWhenWorkspaceChanges() async {
        let harness = AppBranchTestSupport.makeHarness(
            frontmostApplication: .init(
                bundleIdentifier: "com.apple.Safari",
                localizedName: "Safari",
                processIdentifier: 42,
                runningApplication: nil
            )
        )
        let monitor = harness.monitor
        var receivedApps: [AppInfo] = []

        let observerID = monitor.addObserver { appInfo in
            if let appInfo {
                receivedApps.append(appInfo)
            }
        }

        monitor.startMonitoring()
        await harness.drainCallbacks()

        harness.workspace.frontmostApplication = .init(
            bundleIdentifier: "com.apple.Terminal",
            localizedName: "Terminal",
            processIdentifier: 84,
            runningApplication: nil
        )
        harness.workspace.simulateActivationChange()
        await harness.drainCallbacks()

        #expect(receivedApps.map(\.bundleIdentifier) == ["com.apple.Safari", "com.apple.Terminal"])

        monitor.removeObserver(observerID)
        monitor.stopMonitoring()
        await harness.drainCallbacks()
    }
}
#endif
