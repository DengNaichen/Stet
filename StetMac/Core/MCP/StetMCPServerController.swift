#if os(macOS)
    import Foundation
    import os

    nonisolated protocol StetMCPRuntimeServing: Sendable {
        func run() async throws
        func stop() async
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

        func run() async throws {
            try await protocolServer.start()
            do {
                try await httpServer.run()
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
            settingsStore: DictationSettingsStore,
            defaults: UserDefaults = .standard
        ) -> StetMCPServerController {
            let pipelineFactory = DictationPipelineFactory.live()
            return StetMCPServerController(defaults: defaults) {
                let coordinator = MCPTranscriptionCoordinator(
                    settingsStore: settingsStore,
                    pipelineFactory: pipelineFactory
                )
                let protocolServer = StetMCPProtocolServer(transcriber: coordinator)
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
            guard serverTask == nil else { return }

            let server = makeServer()
            let logger = self.logger
            self.server = server
            serverTask = Task {
                do {
                    try await server.run()
                    logger.info("Stet MCP server stopped.")
                } catch is CancellationError {
                    logger.info("Stet MCP server cancelled.")
                } catch {
                    logger.error("Stet MCP server failed: \(error.localizedDescription)")
                }
            }
        }

        func stop() {
            guard let server else { return }
            serverTask?.cancel()
            serverTask = nil
            self.server = nil
            Task {
                await server.stop()
            }
        }

        deinit {
            serverTask?.cancel()
        }
    }
#endif
