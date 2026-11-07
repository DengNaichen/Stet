import Foundation
import MCP

struct StetMCPHTTPResult: Sendable {
    nonisolated let statusCode: Int
    nonisolated let headers: [String: String]
    nonisolated let body: Data?
}

actor StetMCPProtocolServer {
    static let listMeetingsToolName = MCPRecordingTools.listMeetingsToolName
    static let listUnorganizedMeetingsToolName = MCPRecordingTools.listUnorganizedMeetingsToolName
    static let getMeetingTranscriptToolName = MCPRecordingTools.getMeetingTranscriptToolName

    private static let serverName = "stet"
    private static let serverVersion = "1.0.0"
    private static let serverTitle = "Stet Meetings"
    private static let serverInstructions =
        "Read Stet meeting recordings, synchronize expected meetings, and access local calendars."
    private static let serverCapabilities = Server.Capabilities(tools: .init(listChanged: false))

    private let recordings: MCPRecordingTools
    private let expectedMeetings: MCPExpectedMeetingTools
    private let calendar: MCPCalendarTools?
    private let transport = StatelessHTTPServerTransport()
    private let server: Server
    private var started = false
    private var toolTasks: [UUID: Task<CallTool.Result, Never>] = [:]

    init(
        catalog: any MCPMeetingServing,
        expectedMeetings: (any ExpectedMeetingServing)? = nil,
        calendarReadClient: (any CalendarReadClient)? = nil,
        calendarWriteClient: (any CalendarWriteClient)? = nil
    ) {
        recordings = MCPRecordingTools(catalog: catalog)
        self.expectedMeetings = MCPExpectedMeetingTools(service: expectedMeetings)
        let readClient = calendarReadClient ?? calendarWriteClient
        calendar = readClient.map { MCPCalendarTools(readClient: $0, writeClient: calendarWriteClient) }
        server = Server(
            name: Self.serverName,
            version: Self.serverVersion,
            title: Self.serverTitle,
            instructions: Self.serverInstructions,
            capabilities: Self.serverCapabilities
        )
    }

    func start() async throws {
        guard !started else { return }
        let tools = MCPRecordingTools.tools + MCPExpectedMeetingTools.tools + (calendar?.tools ?? [])
        await server.withMethodHandler(ListTools.self) { _ in .init(tools: tools) }
        await server.withMethodHandler(CallTool.self) { [weak self] parameters in
            guard let self else { return MCPToolSupport.error("Server stopped.") }
            return await self.callTool(parameters)
        }
        try await server.start(transport: transport)
        await server.withMethodHandler(Initialize.self) { params in
            Self.initializeResult(requestedProtocolVersion: params.protocolVersion)
        }
        started = true
    }

    func stop() async {
        guard started else { return }
        started = false
        let tasks = Array(toolTasks.values)
        toolTasks.removeAll()
        for task in tasks { task.cancel() }
        await server.stop()
        for task in tasks { _ = await task.value }
    }

    private func callTool(_ parameters: CallTool.Parameters) async -> CallTool.Result {
        guard started else { return MCPToolSupport.error("Server stopped.") }
        let id = UUID()
        let task = Task { [recordings, expectedMeetings, calendar] in
            guard !Task.isCancelled else { return MCPToolSupport.error("Request cancelled.") }
            if MCPRecordingTools.names.contains(parameters.name) { return await recordings.call(parameters) }
            if MCPExpectedMeetingTools.names.contains(parameters.name) {
                return await expectedMeetings.call(parameters)
            }
            if MCPCalendarTools.readNames.contains(parameters.name)
                || MCPCalendarTools.writeNames.contains(parameters.name)
            {
                guard let calendar else { return MCPToolSupport.error("Calendar access is unavailable.") }
                return await calendar.call(parameters)
            }
            return MCPToolSupport.error("Unknown tool: \(parameters.name)")
        }
        toolTasks[id] = task
        defer { toolTasks.removeValue(forKey: id) }
        return await task.value
    }

    func handleHTTPRequest(_ request: HTTPRequest) async -> HTTPResponse {
        await transport.handleRequest(request)
    }

    func handleRawRequest(
        method: String,
        headers: [String: String],
        body: Data?,
        path: String = "/mcp"
    ) async -> StetMCPHTTPResult {
        let response = await transport.handleRequest(
            HTTPRequest(method: method, headers: headers, body: body, path: path)
        )
        return StetMCPHTTPResult(
            statusCode: response.statusCode,
            headers: response.headers,
            body: response.bodyData
        )
    }

    private nonisolated static func initializeResult(requestedProtocolVersion: String) -> Initialize.Result {
        Initialize.Result(
            protocolVersion: Version.supported.contains(requestedProtocolVersion)
                ? requestedProtocolVersion : Version.latest,
            capabilities: serverCapabilities,
            serverInfo: .init(name: serverName, version: serverVersion, title: serverTitle),
            instructions: serverInstructions
        )
    }
}
