# AGENTS.md

## Repository model

This is the public canonical monorepo for Stet. macOS and iOS apps live in the
same repository as first-class subtrees:

- `Stet.xcodeproj`, [StetMac/](StetMac), [StetVisuals/](StetVisuals), and shared packages — macOS app
- [StetMobile/](StetMobile) — iOS app, keyboard extension, and Live Activity

Shared Swift packages (`StetEngine`, etc.) live under [Packages/](Packages) and
are referenced by both platforms.

## Entry points

- [`CLAUDE.md`](CLAUDE.md) symlinks to this file for Claude Code; it is not a separate guide.
- Tool adapters (no agent knowledge): [`.cursor/`](.cursor/), [`.claude/`](.claude/), [`.codex/`](.codex/).
- Project docs: [`docs/index.md`](docs/index.md), [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md), [`docs/specs/`](docs/specs/index.md).
- Apple platform reference (read on demand): [`reference/apple-platform/index.md`](reference/apple-platform/index.md).
- For macOS or shared code, work from the repository root and read the relevant module docs under [docs/](docs).
- For iOS code, read [`StetMobile/AGENTS.md`](StetMobile/AGENTS.md) and work from [StetMobile/](StetMobile).

## Build and validation

开始代码修改、创建分支/worktree、提交 PR 或清理已合并工作时，读取
[git-workflow](.agents/skills/git-workflow/SKILL.md)。它拥有跨 agent 的 Git 流程；
环境初始化继续由 `scripts/setup-worktree` 负责。

- Stable macOS build: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer make build`
- macOS tests: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer make test`
- iOS simulator build: `make ios-build`; it uses stable Xcode per-command and
  the selected Xcode’s simulator SDK. Override `IOS_DEVELOPER_DIR` when needed;
  it does not change the global Xcode selection.
- Formatting and lint: `make lint` (first prepare documentation dependencies with `make docs-lint-setup`).
- File references in prose use Markdown links; commands, templates and generated/local-only paths remain code. `make docs-lint` checks local links and headings, including legacy specs; imported `reference/` content is excluded.

For macOS rewrite model additions, removals, defaults, or availability changes, edit [StetMac/Resources/rewrite-models.json](StetMac/Resources/rewrite-models.json), increment its `revision`, and run `python3 scripts/validate-rewrite-models.py`; do not modify [Packages/StetEngine/Sources/StetCore/RewriteModel.swift](Packages/StetEngine/Sources/StetCore/RewriteModel.swift), which remains the iOS compatibility model list.

Do not add model payloads or downloaded runtime frameworks to Git. Release
scripts and signing config live under [scripts/](scripts); canonical GitHub Actions
workflows live at repository root [.github/workflows/](.github/workflows) (see [.github/WORKFLOWS.md](.github/WORKFLOWS.md)).

Do not run Git index-writing commands in parallel. Preserve unrelated user
changes and use small, verifiable commits.

## Active Technologies
- Swift 5.10; C++17 only where the existing FunASR runtime already requires it; Python 3.10+ for the existing calibration probe + AVFoundation/AVCapture, FluidAudio pinned at `0346057d8245b5e7ace6965d499f85d93e803ef1`, existing SherpaOnnxPackage speaker-embedding API, existing FunASRRuntime, SwiftData, Security/Keychain (009-passive-speech-gate)
- SwiftData `HistoryEntry` for accepted transcript metadata and speaker regions; local non-synchronizing Keychain item for aggregate speaker profiles; raw pending audio only in RAM; accepted turn WAVs only in a dedicated temporary directory (009-passive-speech-gate)

## Recent Changes
- 009-passive-speech-gate: Added Swift 5.10; C++17 only where the existing FunASR runtime already requires it; Python 3.10+ for the existing calibration probe + AVFoundation/AVCapture, FluidAudio pinned at `0346057d8245b5e7ace6965d499f85d93e803ef1`, existing SherpaOnnxPackage speaker-embedding API, existing FunASRRuntime, SwiftData, Security/Keychain
