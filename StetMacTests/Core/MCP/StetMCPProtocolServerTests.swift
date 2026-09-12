import Foundation
import Testing

@testable import Stet

@MainActor
@Suite("Stet MCP Protocol Server")
struct StetMCPProtocolServerTests {
    @Test func listsTheThreeMeetingTools() async throws {
        let server = StetMCPProtocolServer(catalog: MCPStubMeetingCatalog())
        try await server.start()
        defer { Task { await server.stop() } }
        try await initialize(server)

        let listResponse = await server.handleRawRequest(
            method: "POST",
            headers: protocolHeaders,
            body: try jsonData([
                "jsonrpc": "2.0",
                "id": 2,
                "method": "tools/list",
                "params": [:],
            ])
        )
        #expect(listResponse.statusCode == 200)
        let listJSON = try responseJSON(listResponse)
        let listResult = try #require(listJSON["result"] as? [String: Any])
        let tools = try #require(listResult["tools"] as? [[String: Any]])
        #expect(
            tools.map { $0["name"] as? String } == [
                StetMCPProtocolServer.listMeetingsToolName,
                StetMCPProtocolServer.listUnorganizedMeetingsToolName,
                StetMCPProtocolServer.getMeetingTranscriptToolName,
            ])
        #expect(tools.allSatisfy { $0["inputSchema"] != nil && $0["outputSchema"] != nil })
    }

    @Test func callsMeetingToolsAndReturnsStructuredContent() async throws {
        let catalog = MCPStubMeetingCatalog()
        let server = StetMCPProtocolServer(catalog: catalog)
        try await server.start()
        defer { Task { await server.stop() } }
        try await initialize(server)

        let listResponse = await server.handleRawRequest(
            method: "POST",
            headers: protocolHeaders,
            body: try jsonData([
                "jsonrpc": "2.0",
                "id": 2,
                "method": "tools/call",
                "params": [
                    "name": StetMCPProtocolServer.listMeetingsToolName,
                    "arguments": ["limit": 5],
                ],
            ])
        )
        let listResult = try #require(try responseJSON(listResponse)["result"] as? [String: Any])
        #expect(listResult["isError"] as? Bool == false)
        let listStructured = try #require(listResult["structuredContent"] as? [String: Any])
        let meetings = try #require(listStructured["meetings"] as? [[String: Any]])
        #expect(meetings.first?["id"] as? String == "2026-09-12 16-20-01")
        #expect(meetings.first?["status"] as? String == "ready")

        let inboxResponse = await server.handleRawRequest(
            method: "POST",
            headers: protocolHeaders,
            body: try jsonData([
                "jsonrpc": "2.0",
                "id": 3,
                "method": "tools/call",
                "params": [
                    "name": StetMCPProtocolServer.listUnorganizedMeetingsToolName,
                    "arguments": [:],
                ],
            ])
        )
        let inboxResult = try #require(try responseJSON(inboxResponse)["result"] as? [String: Any])
        #expect(inboxResult["isError"] as? Bool == false)

        let getResponse = await server.handleRawRequest(
            method: "POST",
            headers: protocolHeaders,
            body: try jsonData([
                "jsonrpc": "2.0",
                "id": 4,
                "method": "tools/call",
                "params": [
                    "name": StetMCPProtocolServer.getMeetingTranscriptToolName,
                    "arguments": ["meeting_id": "2026-09-12 16-20-01"],
                ],
            ])
        )
        let getResult = try #require(try responseJSON(getResponse)["result"] as? [String: Any])
        #expect(getResult["isError"] as? Bool == false)
        let content = try #require(getResult["content"] as? [[String: Any]])
        #expect(content.first?["text"] as? String == "hello from the room")
        let structured = try #require(getResult["structuredContent"] as? [String: Any])
        #expect(structured["transcript"] as? String == "hello from the room")
        #expect(structured["id"] as? String == "2026-09-12 16-20-01")
    }

    @Test func unknownToolInvalidLimitAndCatalogFailuresAreToolErrors() async throws {
        let catalog = MCPStubMeetingCatalog(error: MCPMeetingError.noReadyMeeting)
        let server = StetMCPProtocolServer(catalog: catalog)
        try await server.start()
        defer { Task { await server.stop() } }
        try await initialize(server)

        let unknown = await server.handleRawRequest(
            method: "POST",
            headers: protocolHeaders,
            body: try jsonData([
                "jsonrpc": "2.0",
                "id": 2,
                "method": "tools/call",
                "params": [
                    "name": "stet_transcribe_audio",
                    "arguments": [:],
                ],
            ])
        )
        let unknownResult = try #require(try responseJSON(unknown)["result"] as? [String: Any])
        #expect(unknownResult["isError"] as? Bool == true)

        let invalidLimit = await server.handleRawRequest(
            method: "POST",
            headers: protocolHeaders,
            body: try jsonData([
                "jsonrpc": "2.0",
                "id": 3,
                "method": "tools/call",
                "params": [
                    "name": StetMCPProtocolServer.listMeetingsToolName,
                    "arguments": ["limit": 0],
                ],
            ])
        )
        let invalidLimitResult = try #require(
            try responseJSON(invalidLimit)["result"] as? [String: Any]
        )
        #expect(invalidLimitResult["isError"] as? Bool == true)

        let emptyInbox = await server.handleRawRequest(
            method: "POST",
            headers: protocolHeaders,
            body: try jsonData([
                "jsonrpc": "2.0",
                "id": 4,
                "method": "tools/call",
                "params": [
                    "name": StetMCPProtocolServer.getMeetingTranscriptToolName,
                    "arguments": [:],
                ],
            ])
        )
        let emptyInboxResult = try #require(
            try responseJSON(emptyInbox)["result"] as? [String: Any]
        )
        #expect(emptyInboxResult["isError"] as? Bool == true)
    }

    @Test func initializeIsIdempotentForClientReconnects() async throws {
        let server = StetMCPProtocolServer(catalog: MCPStubMeetingCatalog())
        try await server.start()
        defer { Task { await server.stop() } }

        try await initialize(server, id: 1)
        try await initialize(server, id: 2)

        let listResponse = await server.handleRawRequest(
            method: "POST",
            headers: protocolHeaders,
            body: try jsonData([
                "jsonrpc": "2.0",
                "id": 3,
                "method": "tools/list",
                "params": [:],
            ])
        )
        #expect(listResponse.statusCode == 200)
        let listJSON = try responseJSON(listResponse)
        #expect(listJSON["error"] == nil)
        let listResult = try #require(listJSON["result"] as? [String: Any])
        let tools = try #require(listResult["tools"] as? [[String: Any]])
        #expect(tools.count == 3)
    }

    @Test func initializeAcceptsStreamableHTTPAcceptHeader() async throws {
        let server = StetMCPProtocolServer(catalog: MCPStubMeetingCatalog())
        try await server.start()
        defer { Task { await server.stop() } }

        try await initialize(
            server,
            headers: [
                "Content-Type": "application/json",
                "Accept": "application/json, text/event-stream",
            ]
        )
    }

    private let protocolVersion = "2025-11-25"

    private var baseHeaders: [String: String] {
        [
            "Content-Type": "application/json",
            "Accept": "application/json",
        ]
    }

    private var protocolHeaders: [String: String] {
        baseHeaders.merging(["MCP-Protocol-Version": protocolVersion]) { _, new in new }
    }

    private func initialize(
        _ server: StetMCPProtocolServer,
        headers: [String: String]? = nil,
        id: Int = 1
    ) async throws {
        let response = await server.handleRawRequest(
            method: "POST",
            headers: headers ?? baseHeaders,
            body: try jsonData([
                "jsonrpc": "2.0",
                "id": id,
                "method": "initialize",
                "params": [
                    "protocolVersion": protocolVersion,
                    "capabilities": [:],
                    "clientInfo": ["name": "StetTests", "version": "1.0"],
                ],
            ])
        )
        #expect(response.statusCode == 200)
        let json = try responseJSON(response)
        #expect(json["error"] == nil)
        let result = try #require(json["result"] as? [String: Any])
        #expect(result["protocolVersion"] as? String == protocolVersion)
        let serverInfo = try #require(result["serverInfo"] as? [String: Any])
        #expect(serverInfo["name"] as? String == "stet")
    }
}

private struct MCPStubMeetingCatalog: MCPMeetingServing {
    var error: MCPMeetingError?
    var summary = MCPMeetingSummary(
        id: "2026-09-12 16-20-01",
        startedAt: "2026-09-12T08:20:01Z",
        endedAt: "2026-09-12T08:45:12Z",
        durationSeconds: 1511,
        status: "ready",
        speakerCount: 2,
        failureMessage: nil
    )

    func listMeetings(limit: Int) throws -> MCPMeetingListOutput {
        if let error { throw error }
        return MCPMeetingListOutput(meetings: Array([summary].prefix(limit)))
    }

    func listUnorganizedMeetings(limit: Int) throws -> MCPMeetingListOutput {
        try listMeetings(limit: limit)
    }

    func meetingTranscript(meetingID: String?) throws -> MCPMeetingTranscriptOutput {
        if let error { throw error }
        return MCPMeetingTranscriptOutput(
            id: meetingID ?? summary.id,
            startedAt: summary.startedAt,
            endedAt: summary.endedAt,
            durationSeconds: summary.durationSeconds,
            status: summary.status,
            speakerCount: summary.speakerCount,
            transcript: "hello from the room",
            failureMessage: nil
        )
    }
}

private func jsonData(_ object: [String: Any]) throws -> Data {
    try JSONSerialization.data(withJSONObject: object)
}

private func responseJSON(_ response: StetMCPHTTPResult) throws -> [String: Any] {
    let body = try #require(response.body)
    return try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
}
