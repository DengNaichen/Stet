# Local Transcription MCP Quickstart

## Requirements

- Stet built and run with Xcode 27 Beta
- SenseVoice available through the normal Stet setup
- The MCP client and audio file on the same Mac

The prototype has no authentication and listens only on `127.0.0.1`.

## Enable the server

For a Debug build:

```sh
defaults write NaichengDeng.Stet.Debug mac.mcpServerEnabled -bool true
```

For a Release build:

```sh
defaults write NaichengDeng.Stet mac.mcpServerEnabled -bool true
```

Restart Stet after changing the preference. The endpoint is:

```text
http://127.0.0.1:49321/mcp
```

To disable the server, write `false` to the same bundle domain and restart Stet.

## MCP client configuration

Use a streamable/stateless HTTP MCP client configuration that points directly to the endpoint. A generic configuration looks like:

```json
{
  "mcpServers": {
    "stet": {
      "type": "http",
      "url": "http://127.0.0.1:49321/mcp"
    }
  }
}
```

Client configuration keys vary, but no command, environment variable, token, or custom header is required.

## Tool call

The server exposes one tool:

```text
stet_transcribe_audio
```

Arguments:

```json
{
  "audio_path": "/absolute/path/to/audio.m4a"
}
```

The file must be an existing, readable regular file and must be readable by `AVAudioFile`. WAV and M4A are suitable formats for validation. Stet does not convert unsupported formats, modify the source file, or delete it.

The response includes final text content and this structured result:

```json
{
  "text": "最终文本",
  "raw_text": "SenseVoice 原始转写",
  "language_code": "zh",
  "rewrite_applied": true,
  "warnings": []
}
```

Rewrite uses Stet's current provider, model, language, and personal dictionary. If rewrite is disabled, the raw transcript is returned. If rewrite fails, the raw transcript is returned with a warning.

## Build and test with Xcode 27 Beta

Use the beta toolchain explicitly when it is not the system-selected Xcode:

```sh
DEVELOPER_DIR=/path/to/Xcode-beta.app/Contents/Developer make ci-build
DEVELOPER_DIR=/path/to/Xcode-beta.app/Contents/Developer make test
```

The opt-in live coordinator test accepts a colon-separated WAV/M4A list:

```sh
STET_MCP_E2E_AUDIO_PATHS=/absolute/sample.wav:/absolute/sample.m4a \
  DEVELOPER_DIR=/path/to/Xcode-beta.app/Contents/Developer make test
```
