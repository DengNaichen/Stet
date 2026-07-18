#if os(macOS)
    import Foundation
    import Testing

    @testable import Stet

    extension AppBranchTests {
        @Test("startMonitoring sets isMonitoring to true")
        func startMonitoringSetsIsMonitoringToTrue() async {
            let harness = AppBranchTestSupport.makeHarness()
            let monitor = harness.monitor

            monitor.startMonitoring()
            await harness.drainCallbacks()

            #expect(monitor.isMonitoring)
            #expect(harness.workspace.observerCount == 1)

            monitor.stopMonitoring()
            await harness.drainCallbacks()
        }

        @Test("startMonitoring initializes currentApp")
        func startMonitoringInitializesCurrentApp() async throws {
            let harness = AppBranchTestSupport.makeHarness(
                frontmostApplication: .init(
                    bundleIdentifier: "com.apple.TextEdit",
                    localizedName: "TextEdit",
                    processIdentifier: 101,
                    runningApplication: nil
                )
            )
            let monitor = harness.monitor

            monitor.startMonitoring()
            await harness.drainCallbacks()

            let appInfo = try #require(monitor.currentApp)
            #expect(appInfo.bundleIdentifier == "com.apple.TextEdit")
            #expect(appInfo.localizedName == "TextEdit")
            #expect(appInfo.processIdentifier == 101)
            #expect(appInfo.runningApplication == nil)

            monitor.stopMonitoring()
            await harness.drainCallbacks()
        }

        @Test("startMonitoring is idempotent")
        func startMonitoringIsIdempotent() async {
            let harness = AppBranchTestSupport.makeHarness()
            let monitor = harness.monitor

            monitor.startMonitoring()
            monitor.startMonitoring()
            await harness.drainCallbacks()

            #expect(monitor.isMonitoring)
            #expect(harness.workspace.activeObserverCount == 1)

            monitor.stopMonitoring()
            await harness.drainCallbacks()
        }

        @Test("stopMonitoring sets isMonitoring to false")
        func stopMonitoringSetsIsMonitoringToFalse() async {
            let harness = AppBranchTestSupport.makeHarness()
            let monitor = harness.monitor

            monitor.startMonitoring()
            await harness.drainCallbacks()
            #expect(monitor.isMonitoring)

            monitor.stopMonitoring()
            await harness.drainCallbacks()

            #expect(!monitor.isMonitoring)
            #expect(harness.workspace.removedObserverCount == 1)
        }

        @Test("stopMonitoring is idempotent")
        func stopMonitoringIsIdempotent() async {
            let harness = AppBranchTestSupport.makeHarness()
            let monitor = harness.monitor

            monitor.startMonitoring()
            await harness.drainCallbacks()

            monitor.stopMonitoring()
            monitor.stopMonitoring()
            await harness.drainCallbacks()

            #expect(!monitor.isMonitoring)
            #expect(harness.workspace.removedObserverCount == 1)
        }
    }
#endif
