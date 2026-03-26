#if os(macOS)
    import Foundation
    import Testing

    @testable import Stet

    extension AppBranchTests {
        @Test("setExcludedBundleID configures exclusion")
        func setExcludedBundleIDConfiguresExclusion() {
            let harness = AppBranchTestSupport.makeHarness()
            let monitor = harness.monitor

            #expect(monitor.excludedBundleID == nil)

            monitor.setExcludedBundleID("com.apple.Safari")
            #expect(monitor.excludedBundleID == "com.apple.Safari")

            monitor.setExcludedBundleID(nil)
            #expect(monitor.excludedBundleID == nil)
        }

        @Test("setExcludedBundleID can be called multiple times")
        func setExcludedBundleIDCanBeCalledMultipleTimes() {
            let harness = AppBranchTestSupport.makeHarness()
            let monitor = harness.monitor

            monitor.setExcludedBundleID("com.apple.Safari")
            #expect(monitor.excludedBundleID == "com.apple.Safari")

            monitor.setExcludedBundleID("com.apple.Mail")
            #expect(monitor.excludedBundleID == "com.apple.Mail")

            monitor.setExcludedBundleID("com.apple.Finder")
            #expect(monitor.excludedBundleID == "com.apple.Finder")

            monitor.setExcludedBundleID(nil)
            #expect(monitor.excludedBundleID == nil)
        }

        @Test("excluded app returns nil when there is no previous non-excluded app")
        func excludedAppReturnsNilWhenNoPreviousNonExcludedApp() {
            let harness = AppBranchTestSupport.makeHarness(
                frontmostApplication: .init(
                    bundleIdentifier: "com.apple.Safari",
                    localizedName: "Safari",
                    processIdentifier: 42,
                    runningApplication: nil
                )
            )
            let monitor = harness.monitor

            monitor.setExcludedBundleID("com.apple.Safari")

            #expect(monitor.currentApp == nil)
        }

        @Test("excluded app falls back to the previous non-excluded app")
        func excludedAppFallsBackToPreviousNonExcludedApp() async {
            let harness = AppBranchTestSupport.makeHarness(
                frontmostApplication: .init(
                    bundleIdentifier: "com.apple.Mail",
                    localizedName: "Mail",
                    processIdentifier: 12,
                    runningApplication: nil
                )
            )
            let monitor = harness.monitor

            monitor.startMonitoring()
            await harness.drainCallbacks()

            monitor.setExcludedBundleID("com.apple.Safari")
            harness.workspace.frontmostApplication = .init(
                bundleIdentifier: "com.apple.Safari",
                localizedName: "Safari",
                processIdentifier: 99,
                runningApplication: nil
            )

            let appInfo = try? #require(monitor.currentApp)
            #expect(appInfo?.bundleIdentifier == "com.apple.Mail")

            monitor.stopMonitoring()
            await harness.drainCallbacks()
        }
    }
#endif
