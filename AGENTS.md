# AGENTS.md

## Repository model

This is the private canonical monorepo. `Public/Stet/` is the allowlisted public
projection and `Private/StetMobile/` is private. Never copy private files into the
public subtree and never push a monorepo commit directly to the public remote.

## Entry points

- For macOS or shared public code, read `Public/Stet/AGENTS.md` and work from
  `Public/Stet/`.
- For iOS code, work from `Private/StetMobile/`. Shared sources are referenced
  from `Public/Stet/Packages/StetEngine` and `Public/Stet/StetVisuals`.
- Keep root-level changes limited to monorepo governance, CI, and orchestration.

## Build and validation

- Stable macOS build: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer make build`
- macOS tests: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer make test`
- iOS 27 simulator build: `make ios-build`; it uses Xcode Beta per-command and
  does not change the global Xcode selection.
- Formatting and lint: `make lint`
- Public boundary: `make verify-public`

Do not add model payloads or downloaded runtime frameworks to Git. Do not change
public release automation from the monorepo root; release changes belong inside
`Public/Stet/`.

Do not run Git index-writing commands in parallel. Preserve unrelated user
changes and use small, verifiable commits.

## Active Technologies
- Swift 5.10; C++17 only where the existing FunASR runtime already requires it; Python 3.10+ for the existing calibration probe + AVFoundation/AVCapture, FluidAudio pinned at `0346057d8245b5e7ace6965d499f85d93e803ef1`, existing SherpaOnnxPackage speaker-embedding API, existing FunASRRuntime, SwiftData, Security/Keychain (009-passive-speech-gate)
- SwiftData `HistoryEntry` for accepted transcript metadata and speaker regions; local non-synchronizing Keychain item for aggregate speaker profiles; raw pending audio only in RAM; accepted turn WAVs only in a dedicated temporary directory (009-passive-speech-gate)

## Recent Changes
- 009-passive-speech-gate: Added Swift 5.10; C++17 only where the existing FunASR runtime already requires it; Python 3.10+ for the existing calibration probe + AVFoundation/AVCapture, FluidAudio pinned at `0346057d8245b5e7ace6965d499f85d93e803ef1`, existing SherpaOnnxPackage speaker-embedding API, existing FunASRRuntime, SwiftData, Security/Keychain
