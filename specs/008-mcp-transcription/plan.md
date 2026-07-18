# Implementation Plan: Local Transcription MCP

## Summary

Add an app-hosted, opt-in MCP server around Stet's existing file transcription and rewrite pipeline. The implementation stays intentionally narrow: one localhost endpoint and one local-file tool.

## Technical Context

- Platform: macOS
- Language: Swift
- Toolchain used for implementation: Xcode 27 Beta
- MCP: Swift MCP SDK `0.12.1`, stateless HTTP transport
- Listener: SwiftNIO (`NIOCore`, `NIOHTTP1`, `NIOPosix`)
- Audio: existing `SenseVoiceFileTranscriber` and `AVAudioFile` decoding
- Rewrite: existing `TextRewriteService` through `DictationPipelineFactory`
- Testing: Swift Testing

## Design

### Coordinator

`MCPTranscriptionCoordinator` is an actor with an explicit processing gate. It validates the local path, reads a new `DictationSettingsSnapshot`, creates the existing pipeline, transcribes the file, and optionally submits `TextRewriteRequest.cleanup` with `.ai` audience. The gate spans asynchronous transcription and rewrite work so actor reentrancy cannot overlap calls.

### Protocol server

`StetMCPProtocolServer` owns the MCP SDK stateless HTTP transport and registers `initialize`, `tools/list`, and `tools/call` behavior. The tool returns final text as text content as well as the documented structured object.

### HTTP listener

`StetMCPHTTPServer` is a thin SwiftNIO listener bound to `127.0.0.1:49321`. It forwards only `/mcp` requests to the SDK transport. Streaming and server-sent events are unnecessary for this stateless tool.

### Lifecycle

`StetMCPServerController` checks `mac.mcpServerEnabled` and starts a background server task. `MacAppModel` owns the controller for the lifetime of the app. Bind errors are logged and contained within the controller.

## Project Structure

### Relevant Source Code

- `Stet/Core/MCP/MCPTranscriptionCoordinator.swift`
- `Stet/Core/MCP/StetMCPProtocolServer.swift`
- `Stet/Core/MCP/StetMCPHTTPServer.swift`
- `Stet/Core/MCP/StetMCPServerController.swift`
- `Stet/App/Lifecycle/MacAppModel.swift`
- `Stet/App/Lifecycle/MacAppBootstrapper.swift`
- `Stet/Shared/Utilities/MacPreferences.swift`
- `Stet.xcodeproj/project.pbxproj`

### Relevant Tests

- `StetTests/Core/MCP/MCPTranscriptionCoordinatorTests.swift`
- `StetTests/Core/MCP/StetMCPHTTPServerTests.swift`
- `StetTests/Core/MCP/StetMCPProtocolServerTests.swift`
- `StetTests/Core/MCP/StetMCPServerControllerTests.swift`
- `StetTests/App/Lifecycle/MacAppBootstrapperTests.swift`

### Documentation

- `specs/008-mcp-transcription/spec.md`
- `specs/008-mcp-transcription/plan.md`
- `specs/008-mcp-transcription/quickstart.md`
- `specs/008-mcp-transcription/contracts/stet-transcribe-audio.schema.json`

## Implementation Observations

- An actor alone does not serialize an operation across `await` suspension points, so the coordinator needs a small FIFO gate.
- Reusing `DictationPipelineFactory` keeps model selection, rewrite provider configuration, detected language, and personal spellings aligned with interactive dictation.
- The MCP SDK owns protocol validation and JSON-RPC encoding; the NIO layer only adapts HTTP request and response values.
- The hidden preference is read at app startup. Changing it requires restarting Stet.

## Complexity Tracking

The only new external dependency is the pinned MCP SDK. SwiftNIO was already present transitively but is now linked directly because the app owns the listener. No new process, database, media converter, or UI state is introduced.
