#if os(macOS)
import Foundation
import Testing

@testable import Stet

extension AppBranchTests {
    @Test("currentApp returns correct app when not monitoring")
    func currentAppReturnsCorrectAppWhenNotMonitoring() {
        let harness = AppBranchTestSupport.makeHarness(
            frontmostApplication: .init(
                bundleIdentifier: "com.apple.Safari",
                localizedName: "Safari",
                processIdentifier: 42,
                runningApplication: nil
            )
        )

        let appInfo = harness.monitor.currentApp
        #expect(appInfo?.bundleIdentifier == "com.apple.Safari")
        #expect(appInfo?.localizedName == "Safari")
        #expect(appInfo?.processIdentifier == 42)
    }

    @Test("currentApp reflects workspace changes immediately")
    func currentAppReflectsWorkspaceChangesImmediately() {
        let harness = AppBranchTestSupport.makeHarness(
            frontmostApplication: .init(
                bundleIdentifier: "com.apple.Safari",
                localizedName: "Safari",
                processIdentifier: 42,
                runningApplication: nil
            )
        )

        #expect(harness.monitor.currentApp?.bundleIdentifier == "com.apple.Safari")

        harness.workspace.frontmostApplication = .init(
            bundleIdentifier: "com.apple.Mail",
            localizedName: "Mail",
            processIdentifier: 99,
            runningApplication: nil
        )

        #expect(harness.monitor.currentApp?.bundleIdentifier == "com.apple.Mail")
    }

    @Test("previousApp is tracked correctly across app switches")
    func previousAppIsTrackedCorrectlyAcrossAppSwitches() async {
        let harness = AppBranchTestSupport.makeHarness(
            frontmostApplication: .init(
                bundleIdentifier: "com.apple.Safari",
                localizedName: "Safari",
                processIdentifier: 42,
                runningApplication: nil
            )
        )
        let monitor = harness.monitor

        monitor.startMonitoring()
        await harness.drainCallbacks()

        #expect(monitor.currentApp?.bundleIdentifier == "com.apple.Safari")

        harness.workspace.frontmostApplication = .init(
            bundleIdentifier: "com.apple.Mail",
            localizedName: "Mail",
            processIdentifier: 99,
            runningApplication: nil
        )
        harness.workspace.simulateActivationChange()
        await harness.drainCallbacks()

        #expect(monitor.currentApp?.bundleIdentifier == "com.apple.Mail")

        monitor.setExcludedBundleID("com.apple.Mail")
        #expect(monitor.currentApp?.bundleIdentifier == "com.apple.Safari")

        monitor.stopMonitoring()
        await harness.drainCallbacks()
    }

    @Test("isOwnHostApplication is set correctly")
    func isOwnHostApplicationIsSetCorrectly() {
        let hostBundleID = Bundle.main.bundleIdentifier ?? "com.stet.app"

        let harness = AppBranchTestSupport.makeHarness(
            frontmostApplication: .init(
                bundleIdentifier: hostBundleID,
                localizedName: "Stet",
                processIdentifier: 1234,
                runningApplication: nil
            )
        )

        let appInfo = harness.monitor.currentApp
        #expect(appInfo?.isOwnHostApplication == true)
    }

    @Test("isOwnHostApplication is false for other apps")
    func isOwnHostApplicationIsFalseForOtherApps() {
        let harness = AppBranchTestSupport.makeHarness(
            frontmostApplication: .init(
                bundleIdentifier: "com.apple.Safari",
                localizedName: "Safari",
                processIdentifier: 42,
                runningApplication: nil
            )
        )

        let appInfo = harness.monitor.currentApp
        #expect(appInfo?.isOwnHostApplication == false)
    }
}
#endif
