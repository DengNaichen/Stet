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
