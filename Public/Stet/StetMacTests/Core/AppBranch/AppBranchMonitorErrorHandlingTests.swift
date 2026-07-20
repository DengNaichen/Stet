#if os(macOS)
    import Foundation
    import Testing

    @testable import Stet

    extension AppBranchTests {
        @Test("currentApp handles nil frontmost application gracefully")
        func currentAppHandlesNilFrontmostAppGracefully() {
            let harness = AppBranchTestSupport.makeHarness(frontmostApplication: nil)
            #expect(harness.monitor.currentApp == nil)
        }

        @Test("startMonitoring handles initialization errors gracefully")
        func startMonitoringHandlesInitializationErrorsGracefully() async {
            let harness = AppBranchTestSupport.makeHarness()
            let monitor = harness.monitor

            monitor.startMonitoring()
            await harness.drainCallbacks()

            #expect(monitor.isMonitoring)

            monitor.stopMonitoring()
            await harness.drainCallbacks()
        }

        @Test("stopMonitoring is safe when not monitoring")
        func stopMonitoringIsSafeWhenNotMonitoring() async {
            let harness = AppBranchTestSupport.makeHarness()
            let monitor = harness.monitor

            monitor.stopMonitoring()
            await harness.drainCallbacks()

            #expect(!monitor.isMonitoring)
        }

        @Test("rapid start stop calls leave monitor stopped")
        func rapidStartStopCallsLeaveMonitorStopped() async {
            let harness = AppBranchTestSupport.makeHarness()
            let monitor = harness.monitor

            for _ in 0..<5 {
                monitor.startMonitoring()
                monitor.stopMonitoring()
            }

            await harness.drainCallbacks()

            #expect(!monitor.isMonitoring)
            #expect(harness.workspace.observerCount == harness.workspace.removedObserverCount)
        }

        @Test("currentApp returns nil when frontmost app has no bundle identifier")
        func currentAppReturnsNilWhenBundleIdentifierMissing() {
            let harness = AppBranchTestSupport.makeHarness(
                frontmostApplication: .init(
                    bundleIdentifier: nil,
                    localizedName: "Unnamed",
                    processIdentifier: 501,
                    runningApplication: nil
                )
            )

            #expect(harness.monitor.currentApp == nil)
        }
    }
#endif
