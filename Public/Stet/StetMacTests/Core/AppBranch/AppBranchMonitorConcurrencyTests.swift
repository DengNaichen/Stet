#if os(macOS)
    import Foundation
    import Testing

    @testable import Stet

    extension AppBranchTests {
        @Test("concurrent addObserver calls are thread-safe")
        func concurrentAddObserverCallsAreThreadSafe() async {
            let harness = AppBranchTestSupport.makeHarness()
            let monitor = harness.monitor

            await withTaskGroup(of: UUID.self) { group in
                for _ in 0..<100 {
                    group.addTask {
                        monitor.addObserver { _ in }
                    }
                }

                var observerIDs: Set<UUID> = []
                for await observerID in group {
                    observerIDs.insert(observerID)
                }

                #expect(observerIDs.count == 100)

                for observerID in observerIDs {
                    monitor.removeObserver(observerID)
                }
            }
        }

        @Test("concurrent removeObserver calls are thread-safe")
        func concurrentRemoveObserverCallsAreThreadSafe() async {
            let harness = AppBranchTestSupport.makeHarness()
            let monitor = harness.monitor

            var observerIDs: [UUID] = []
            for _ in 0..<100 {
                observerIDs.append(monitor.addObserver { _ in })
            }

            await withTaskGroup(of: Void.self) { group in
                for observerID in observerIDs {
                    group.addTask {
                        monitor.removeObserver(observerID)
                    }
                }
            }

            #expect(true)
        }

        @Test("concurrent startMonitoring and stopMonitoring calls are safe")
        func concurrentStartStopCallsAreSafe() async {
            let harness = AppBranchTestSupport.makeHarness()
            let monitor = harness.monitor

            await withTaskGroup(of: Void.self) { group in
                for i in 0..<50 {
                    group.addTask {
                        if i % 2 == 0 {
                            monitor.startMonitoring()
                        } else {
                            monitor.stopMonitoring()
                        }
                    }
                }
            }

            await harness.drainCallbacks()

            monitor.stopMonitoring()
            await harness.drainCallbacks()
        }

        @Test("concurrent setExcludedBundleID calls are thread-safe")
        func concurrentSetExcludedBundleIDCallsAreThreadSafe() async {
            let harness = AppBranchTestSupport.makeHarness()
            let monitor = harness.monitor

            let bundleIDs = [
                "com.apple.Safari",
                "com.apple.Mail",
                "com.apple.Finder",
                "com.apple.Terminal",
                nil,
            ]

            await withTaskGroup(of: Void.self) { group in
                for _ in 0..<100 {
                    group.addTask {
                        let randomID = bundleIDs.randomElement() ?? nil
                        monitor.setExcludedBundleID(randomID)
                    }
                }
            }

            #expect(true)
        }

        @Test("concurrent currentApp reads are thread-safe")
        func concurrentCurrentAppReadsAreThreadSafe() async {
            let harness = AppBranchTestSupport.makeHarness(
                frontmostApplication: .init(
                    bundleIdentifier: "com.apple.Safari",
                    localizedName: "Safari",
                    processIdentifier: 42,
                    runningApplication: nil
                )
            )
            let monitor = harness.monitor

            await withTaskGroup(of: AppInfo?.self) { group in
                for _ in 0..<100 {
                    group.addTask {
                        monitor.currentApp
                    }
                }

                var results: [AppInfo?] = []
                for await result in group {
                    results.append(result)
                }

                #expect(results.count == 100)
                #expect(results.allSatisfy { $0?.bundleIdentifier == "com.apple.Safari" })
            }
        }
    }
#endif
