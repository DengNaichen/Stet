#if os(macOS)
    import Foundation
    import Testing

    @testable import Stet

    @MainActor
    @Suite("Stet MCP Server Controller")
    struct StetMCPServerControllerTests {
        @Test func disabledPreferenceDoesNotStartServer() async {
            let defaults = TestSupport.makeUserDefaults()
            let runtime = MCPRuntimeRecorder()
            let controller = StetMCPServerController(defaults: defaults) { runtime }

            controller.startIfEnabled()

            try? await Task.sleep(for: .milliseconds(20))
            #expect(await runtime.runCount == 0)
        }

        @Test func enabledPreferenceStartsServerOnlyOnce() async {
            let defaults = TestSupport.makeUserDefaults()
            defaults.set(true, forKey: MacPreferences.mcpServerEnabled)
            let runtime = MCPRuntimeRecorder()
            let controller = StetMCPServerController(defaults: defaults) { runtime }

            controller.startIfEnabled()
            controller.startIfEnabled()

            let started = await TestSupport.eventuallyAsync {
                await runtime.runCount == 1
            }
            #expect(started)
        }

        @Test func stopForwardsToRuntime() async {
            let defaults = TestSupport.makeUserDefaults()
            defaults.set(true, forKey: MacPreferences.mcpServerEnabled)
            let runtime = MCPRuntimeRecorder()
            let controller = StetMCPServerController(defaults: defaults) { runtime }
            controller.startIfEnabled()

            _ = await TestSupport.eventuallyAsync {
                await runtime.runCount == 1
            }
            await controller.stop()

            let stopped = await TestSupport.eventuallyAsync {
                await runtime.stopCount == 1
            }
            #expect(stopped)
        }

        @Test func enablingWhileStopIsSuspendedRestartsAfterOldRuntimeStops() async throws {
            let defaults = TestSupport.makeUserDefaults()
            let runtime = SuspendedStopRuntime()
            let controller = StetMCPServerController(defaults: defaults) { runtime }
            await controller.setEnabled(true)
            #expect(await TestSupport.eventuallyAsync { await runtime.runCount == 1 })

            let stopping = Task { await controller.setEnabled(false) }
            #expect(await TestSupport.eventuallyAsync { await runtime.isStopping })
            await controller.setEnabled(true)
            await runtime.finishStop()
            await stopping.value

            #expect(await TestSupport.eventuallyAsync { await runtime.runCount == 2 })
            #expect(await TestSupport.eventually { controller.state == .running })
            #expect(defaults.bool(forKey: MacPreferences.mcpServerEnabled))
            await runtime.allowImmediateStops()
            await controller.stop()
        }

        @Test func runtimeStartupFailureDoesNotEscapeIntoAppLifecycle() async {
            let defaults = TestSupport.makeUserDefaults()
            defaults.set(true, forKey: MacPreferences.mcpServerEnabled)
            let runtime = MCPRuntimeRecorder(runError: TestError.expected)
            let controller = StetMCPServerController(defaults: defaults) { runtime }

            controller.startIfEnabled()

            let attempted = await TestSupport.eventuallyAsync {
                await runtime.runCount == 1
            }
            #expect(attempted)
        }

        @Test func setEnabledPersistsAndAppliesImmediately() async {
            let defaults = TestSupport.makeUserDefaults()
            let runtime = MCPRuntimeRecorder()
            let controller = StetMCPServerController(defaults: defaults) { runtime }

            await controller.setEnabled(true)
            let running = await TestSupport.eventuallyAsync {
                await MainActor.run { controller.state == .running }
            }

            #expect(running)
            #expect(defaults.bool(forKey: MacPreferences.mcpServerEnabled))

            await controller.setEnabled(false)

            #expect(controller.state == .disabled)
            #expect(!defaults.bool(forKey: MacPreferences.mcpServerEnabled))
            #expect(await runtime.stopCount == 1)
        }
    }

    private actor SuspendedStopRuntime: StetMCPRuntimeServing {
        private(set) var runCount = 0
        private(set) var isStopping = false
        private var stopContinuation: CheckedContinuation<Void, Never>?
        private var immediateStops = false
        private var runContinuation: CheckedContinuation<Void, Never>?

        func run(onReady: @Sendable () async -> Void) async throws {
            runCount += 1
            await onReady()
            await withCheckedContinuation { runContinuation = $0 }
        }

        func stop() async {
            if !immediateStops {
                isStopping = true
                await withCheckedContinuation { stopContinuation = $0 }
            }
            runContinuation?.resume()
            runContinuation = nil
        }

        func finishStop() {
            stopContinuation?.resume()
            stopContinuation = nil
        }

        func allowImmediateStops() { immediateStops = true }
    }

    private actor MCPRuntimeRecorder: StetMCPRuntimeServing {
        private let runError: (any Error & Sendable)?
        private(set) var runCount = 0
        private(set) var stopCount = 0

        init(runError: (any Error & Sendable)? = nil) {
            self.runError = runError
        }

        func run(onReady: @Sendable () async -> Void) async throws {
            runCount += 1
            if let runError {
                throw runError
            }
            await onReady()
            while !Task.isCancelled {
                try await Task.sleep(for: .seconds(60))
            }
        }

        func stop() async {
            stopCount += 1
        }
    }
#endif
