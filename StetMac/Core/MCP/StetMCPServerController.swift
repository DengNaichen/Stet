#if os(macOS)
    import Foundation
    import os

    nonisolated protocol StetMCPRuntimeServing: Sendable {
        func run(onReady: @Sendable () async -> Void) async throws
        func stop() async
    }

    nonisolated enum StetMCPServerState: Equatable, Sendable {
        case disabled
        case starting
        case running
        case failed(String)
    }

    actor StetMCPServer: StetMCPRuntimeServing {
        private let protocolServer: StetMCPProtocolServer
        private let httpServer: StetMCPHTTPServer

        init(
            protocolServer: StetMCPProtocolServer,
            httpServer: StetMCPHTTPServer
        ) {
            self.protocolServer = protocolServer
            self.httpServer = httpServer
        }

        func run(onReady: @Sendable () async -> Void) async throws {
            try await protocolServer.start()
            do {
                try await httpServer.run(onReady: onReady)
                await protocolServer.stop()
            } catch {
                await protocolServer.stop()
                throw error
            }
        }

        func stop() async {
            await httpServer.stop()
            await protocolServer.stop()
        }
    }

    @MainActor
    final class StetMCPServerController {
        typealias ServerFactory = @Sendable () -> any StetMCPRuntimeServing

        private let defaults: UserDefaults
        private let makeServer: ServerFactory
        private let logger: Logger
        private var server: (any StetMCPRuntimeServing)?
        private var serverTask: Task<Void, Never>?
        private var runID = UUID()
        private(set) var state: StetMCPServerState = .disabled
        var onStateChange: ((StetMCPServerState) -> Void)?

        init(
            defaults: UserDefaults = .standard,
            makeServer: @escaping ServerFactory,
            logger: Logger = Logger(
                subsystem: Bundle.main.bundleIdentifier ?? "com.openwhispr.Stet",
                category: "MCPServer"
            )
        ) {
            self.defaults = defaults
            self.makeServer = makeServer
            self.logger = logger
        }

        static func live(
            livePhaseStore: MCPLiveMeetingPhaseStore,
            expectedMeetings: any ExpectedMeetingServing,
            meetingStore: MeetingRecordingStore = MeetingRecordingStore(),
            defaults: UserDefaults = .standard
        ) -> StetMCPServerController {
            StetMCPServerController(defaults: defaults) {
                let catalog = MCPMeetingCatalog(
                    store: meetingStore,
                    livePhase: { livePhaseStore.current() }
                )
                let protocolServer = StetMCPProtocolServer(
                    catalog: catalog,
                    expectedMeetings: expectedMeetings
                )
                let httpServer = StetMCPHTTPServer { request in
                    await protocolServer.handleHTTPRequest(request)
                }
                return StetMCPServer(
                    protocolServer: protocolServer,
                    httpServer: httpServer
                )
            }
        }

        func startIfEnabled() {
            guard defaults.bool(forKey: MacPreferences.mcpServerEnabled) else { return }
            start()
        }

        func setEnabled(_ enabled: Bool) async {
            defaults.set(enabled, forKey: MacPreferences.mcpServerEnabled)
            if enabled {
                start()
            } else {
                await stop()
            }
        }

        private func start() {
            guard serverTask == nil else { return }

            let server = makeServer()
            let logger = self.logger
            let runID = UUID()
            self.runID = runID
            self.server = server
            updateState(.starting)
            serverTask = Task { [weak self] in
                do {
                    try await server.run {
                        await self?.markRunning(runID: runID)
                    }
                    logger.info("Stet MCP server stopped.")
                    self?.finish(runID: runID, state: .disabled)
                } catch is CancellationError {
                    logger.info("Stet MCP server cancelled.")
                    self?.finish(runID: runID, state: .disabled)
                } catch {
                    logger.error("Stet MCP server failed: \(error.localizedDescription)")
                    self?.finish(runID: runID, state: .failed(error.localizedDescription))
                }
            }
        }

        func stop() async {
            guard let server else {
                updateState(.disabled)
                return
            }
            let task = serverTask
            task?.cancel()
            await server.stop()
            await task?.value
            serverTask = nil
            self.server = nil
            updateState(.disabled)
        }

        private func markRunning(runID: UUID) {
            guard self.runID == runID else { return }
            updateState(.running)
        }

        private func finish(runID: UUID, state: StetMCPServerState) {
            guard self.runID == runID else { return }
            serverTask = nil
            server = nil
            updateState(state)
        }

        private func updateState(_ state: StetMCPServerState) {
            guard self.state != state else { return }
            self.state = state
            onStateChange?(state)
        }

        deinit {
            serverTask?.cancel()
        }
    }
#endif
