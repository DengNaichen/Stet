import Foundation
import Testing

@testable import Stet

@MainActor
@Suite("Stet MCP Protocol Server")
struct StetMCPProtocolServerTests {
    @Test func listsAndCallsTheTranscriptionTool() async throws {
        let transcriber = MCPStubTranscriber(
            output: .init(
                text: "cleaned transcript",
                rawText: "raw transcript",
                languageCode: "zh",
                rewriteApplied: true,
                warnings: []
            )
        )
        let server = StetMCPProtocolServer(transcriber: transcriber)
        try await server.start()
        defer { Task { await server.stop() } }

        let initializeResponse = await server.handleRawRequest(
            method: "POST",
            headers: baseHeaders,
            body: try jsonData([
                "jsonrpc": "2.0",
                "id": 1,
                "method": "initialize",
                "params": [
                    "protocolVersion": protocolVersion,
                    "capabilities": [:],
                    "clientInfo": ["name": "StetTests", "version": "1.0"],
                ],
            ])
        )
        #expect(initializeResponse.statusCode == 200)

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
        let tool = try #require(tools.first)
        #expect(tool["name"] as? String == StetMCPProtocolServer.toolName)
        #expect(tool["inputSchema"] != nil)
        #expect(tool["outputSchema"] != nil)

        let callResponse = await server.handleRawRequest(
            method: "POST",
            headers: protocolHeaders,
            body: try jsonData([
                "jsonrpc": "2.0",
                "id": 3,
                "method": "tools/call",
                "params": [
                    "name": StetMCPProtocolServer.toolName,
                    "arguments": ["audio_path": "/tmp/message.m4a"],
                ],
            ])
        )
        #expect(callResponse.statusCode == 200)
        let callJSON = try responseJSON(callResponse)
        let callResult = try #require(callJSON["result"] as? [String: Any])
        #expect(callResult["isError"] as? Bool == false)
        let content = try #require(callResult["content"] as? [[String: Any]])
        #expect(content.first?["text"] as? String == "cleaned transcript")
        let structured = try #require(callResult["structuredContent"] as? [String: Any])
        #expect(structured["text"] as? String == "cleaned transcript")
        #expect(structured["raw_text"] as? String == "raw transcript")
        #expect(structured["language_code"] as? String == "zh")
        #expect(structured["rewrite_applied"] as? Bool == true)
        #expect(await transcriber.audioPaths == ["/tmp/message.m4a"])
    }

    @Test func invalidArgumentsAndTranscriptionFailuresAreToolErrors() async throws {
        let transcriber = MCPStubTranscriber(error: TestError.expected)
        let server = StetMCPProtocolServer(transcriber: transcriber)
        try await server.start()
        defer { Task { await server.stop() } }

        _ = await server.handleRawRequest(
            method: "POST",
            headers: baseHeaders,
            body: try jsonData([
                "jsonrpc": "2.0",
                "id": 1,
                "method": "initialize",
                "params": [
                    "protocolVersion": protocolVersion,
                    "capabilities": [:],
                    "clientInfo": ["name": "StetTests", "version": "1.0"],
                ],
            ])
        )

        let missingPathResponse = await server.handleRawRequest(
            method: "POST",
            headers: protocolHeaders,
            body: try jsonData([
                "jsonrpc": "2.0",
                "id": 2,
                "method": "tools/call",
                "params": [
                    "name": StetMCPProtocolServer.toolName,
                    "arguments": [:],
                ],
            ])
        )
        let missingPathResult = try #require(
            try responseJSON(missingPathResponse)["result"] as? [String: Any]
        )
        #expect(missingPathResult["isError"] as? Bool == true)

        let failureResponse = await server.handleRawRequest(
            method: "POST",
            headers: protocolHeaders,
            body: try jsonData([
                "jsonrpc": "2.0",
                "id": 3,
                "method": "tools/call",
                "params": [
                    "name": StetMCPProtocolServer.toolName,
                    "arguments": ["audio_path": "/tmp/failure.wav"],
                ],
            ])
        )
        let failureResult = try #require(
            try responseJSON(failureResponse)["result"] as? [String: Any]
        )
        #expect(failureResult["isError"] as? Bool == true)
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
}

private actor MCPStubTranscriber: MCPTranscriptionServing {
    private let output: MCPTranscriptionOutput?
    private let error: (any Error & Sendable)?
    private(set) var audioPaths: [String] = []

    init(output: MCPTranscriptionOutput) {
        self.output = output
        self.error = nil
    }

    init(error: any Error & Sendable) {
        self.output = nil
        self.error = error
    }

    func transcribe(audioPath: String) async throws -> MCPTranscriptionOutput {
        audioPaths.append(audioPath)
        if let error {
            throw error
        }
        return try #require(output)
    }
}

private func jsonData(_ object: [String: Any]) throws -> Data {
    try JSONSerialization.data(withJSONObject: object)
}

private func responseJSON(_ response: StetMCPHTTPResult) throws -> [String: Any] {
    let body = try #require(response.body)
    return try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
}
