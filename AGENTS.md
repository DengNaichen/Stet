# AGENTS.md

## Repository model

This is the public canonical monorepo for Stet. macOS and iOS apps live in the
same repository as first-class subtrees:

- `Public/Stet/` — macOS app (`Stet.xcodeproj`, `StetMac/`, `StetVisuals/`, shared packages)
- `Private/StetMobile/` — iOS app (`StetMobile.xcodeproj`, keyboard extension, Live Activity)

Shared Swift packages (`StetEngine`, etc.) live under `Public/Stet/Packages/` and
are referenced by both platforms.

## Entry points

- [`CLAUDE.md`](CLAUDE.md) symlinks to this file for Claude Code; it is not a separate guide.
- Tool adapters (no agent knowledge): [`.cursor/`](.cursor/README.md), [`.claude/`](.claude/README.md), [`.codex/`](.codex/README.md).
- Harness and durable docs: [`docs/HARNESS.md`](docs/HARNESS.md), [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md), [`docs/specs/`](docs/specs/index.md), [`docs/exec-plans/`](docs/exec-plans/README.md).
- Apple platform reference (read on demand): [`reference/apple-platform/index.md`](reference/apple-platform/index.md).
- For macOS or shared code, read [`Public/Stet/AGENTS.md`](Public/Stet/AGENTS.md) and work from `Public/Stet/`.
- For iOS code, read [`Private/StetMobile/AGENTS.md`](Private/StetMobile/AGENTS.md) and work from `Private/StetMobile/`.
- Keep root-level changes limited to monorepo governance, CI, and orchestration.

## Build and validation

- Stable macOS build: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer make build`
- macOS tests: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer make test`
- iOS 27 simulator build: `make ios-build`; it uses Xcode Beta per-command and
  does not change the global Xcode selection.
- Formatting and lint: `make lint`

Do not add model payloads or downloaded runtime frameworks to Git. Release
scripts and signing config live under `Public/Stet/`; canonical GitHub Actions
workflows live at repository root `.github/workflows/` (see `.github/README.md`).

Do not run Git index-writing commands in parallel. Preserve unrelated user
changes and use small, verifiable commits.

## Active Technologies
- Swift 5.10; C++17 only where the existing FunASR runtime already requires it; Python 3.10+ for the existing calibration probe + AVFoundation/AVCapture, FluidAudio pinned at `0346057d8245b5e7ace6965d499f85d93e803ef1`, existing SherpaOnnxPackage speaker-embedding API, existing FunASRRuntime, SwiftData, Security/Keychain (009-passive-speech-gate)
- SwiftData `HistoryEntry` for accepted transcript metadata and speaker regions; local non-synchronizing Keychain item for aggregate speaker profiles; raw pending audio only in RAM; accepted turn WAVs only in a dedicated temporary directory (009-passive-speech-gate)

## Recent Changes
- 009-passive-speech-gate: Added Swift 5.10; C++17 only where the existing FunASR runtime already requires it; Python 3.10+ for the existing calibration probe + AVFoundation/AVCapture, FluidAudio pinned at `0346057d8245b5e7ace6965d499f85d93e803ef1`, existing SherpaOnnxPackage speaker-embedding API, existing FunASRRuntime, SwiftData, Security/Keychain
