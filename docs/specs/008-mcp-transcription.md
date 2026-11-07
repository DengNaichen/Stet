# Feature Specification: Local Transcription MCP

## Summary

Stet exposes its existing local SenseVoice transcription and optional rewrite pipeline to agents running on the same Mac through a small, opt-in MCP HTTP server.

## User Stories

### Transcribe a local audio file

An MCP client can pass an absolute path to a readable audio file. Stet transcribes the file with the current SenseVoice configuration and returns both the raw transcript and the final text.

### Apply the current rewrite configuration

When rewrite is enabled in Stet, the MCP call uses the current provider, model, language, and personal dictionary. The request is a cleanup request for an AI audience. If rewrite fails, the call still succeeds with the raw transcript and a warning.

### Keep the service local and explicit

The server listens only on `127.0.0.1:49321`, is disabled by default, and runs only while Stet is running. This prototype does not add authentication or a visible settings control.

## Functional Requirements

- The MCP endpoint is `http://127.0.0.1:49321/mcp`.
- The server uses MCP stateless HTTP transport and exposes only `stet_transcribe_audio`.
- The tool accepts one required string property, `audio_path`.
- The path must be absolute and identify an existing, readable, regular file.
- Audio support is limited to formats readable by `AVAudioFile`; no conversion layer is added.
- Every invocation reads a fresh `DictationSettingsSnapshot` and creates the current dictation pipeline.
- Calls are serialized so only one local transcription occupies the ASR pipeline at a time.
- Successful calls return final text as MCP text content and structured output containing:

  ```json
  {
    "text": "最终文本",
    "raw_text": "SenseVoice 原始转写",
    "language_code": "zh",
    "rewrite_applied": true,
    "warnings": []
  }
  ```

- Empty transcription, invalid input, unreadable audio, and transcription failures return an MCP tool result with `isError: true`.
- Disabled rewrite returns the raw transcript with `rewrite_applied: false` and no warning.
- Failed or empty rewrite falls back to the raw transcript with `rewrite_applied: false` and a warning.
- Listener startup failure is logged and does not prevent Stet from running.
- The hidden `mac.mcpServerEnabled` preference is registered as `false` by default.

## Out of Scope

- Hermes or iMessage integration
- Message monitoring, attachment download, and tool routing
- A settings UI
- Authentication, TLS, or remote-network access
- ffmpeg or other format conversion
- Release, signing, notarization, Sparkle, or publishing changes

## Success Criteria

- A local MCP client can initialize, list the single tool, and call it with a WAV or M4A path while Stet is running.
- The source audio file remains present and unchanged after a call.
- Rewrite behavior follows the current Stet settings and degrades to the raw transcript on rewrite failure.
- The app continues normally when the feature is disabled or the port cannot be bound.
