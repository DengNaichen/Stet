# AGENTS.md

## Tech Stack

- Language: Swift
- Platform: macOS native app built from `Stet.xcodeproj`
- UI: SwiftUI with AppKit integration for windows, menu bar, permissions, and platform behavior
- Concurrency and state: Swift Concurrency, Combine, and some Observation usage
- Audio and system frameworks: AVFoundation, CoreAudio, ApplicationServices, Metal, MetalKit, OSLog
- Persistence and local state: `UserDefaults`, Keychain-backed secret storage, some SwiftData models
- Networking and provider integrations: URLSession-based services plus OpenAI-compatible integrations
- Testing: Swift Testing, plus manual validation for platform-heavy flows
- Package management: Swift Package Manager via Xcode
- Common external packages used across the app include `KeyboardShortcuts`, `Sparkle`, and `OpenAI`; feature-specific dependencies should be confirmed in the relevant source and `plan.md`

## Where To Start

- Project start: begin with monorepo [`docs/HARNESS.md`](../../docs/HARNESS.md) and [`docs/ARCHITECTURE.md`](../../docs/ARCHITECTURE.md), then use `StetMac/StetApp.swift`, `StetMac/App/`, and `StetMac/Features/` as the main repository-level entry points.
- Apple platform API guidance: read [`reference/apple-platform/index.md`](../../reference/apple-platform/index.md) on demand; open only the matching topic file.
- Feature start: locate the active entry under [`docs/specs/`](../../docs/specs/index.md), then read the matching Technical Plan under [`docs/exec-plans/active/`](../../docs/exec-plans/README.md) when present.
- Legacy `specs/001–010` and archived feature folders are retired; do not read `docs/archive/specs-legacy/` as current truth.

## Build, Test, and Release

- Daily build command: `make build`
- Daily test command: `make test`
- CI-oriented build without code signing: `make ci-build`
- Formatting commands: `make format` and `make format-lint`
- Lint commands: `make swiftlint` and `make format-lint`
- Direct `xcodebuild` commands in `README.md` are also valid, but prefer the repository `Makefile` targets when possible.
- For feature work, start with the tests listed in the target feature's `plan.md` under `Relevant Tests`, then expand only as needed.
- If a change affects platform-heavy flows that are not well covered by automation, call out the manual validation that was performed or still needed.
- Release entry points are `scripts/release-macos-github.sh` and `scripts/publish-github-release.sh`.
- Release process and GitHub Actions behavior are documented in `docs/release.md` and `.github/workflows/`.
- Do not change release scripts, signing, notarization, Sparkle, or GitHub release automation unless the task is explicitly about release infrastructure.

### Local Xcode Selection

- This machine intentionally has two Xcode installations. Use stable Xcode at `/Applications/Xcode.app` for the macOS `Stet.xcodeproj`; keep `/usr/bin/xcode-select -p` pointing to `/Applications/Xcode.app/Contents/Developer`.
- Use Xcode 27 Beta at `/Applications/Xcode-beta.app` only for the iOS `StetMobile.xcodeproj`. Select it per command with `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`; do not switch the global `xcode-select` path to Beta.
- The current iOS worktree is `StetMobile-remove-whisper/StetMobile.xcodeproj`. If that worktree moves, locate it with `rg --files -g 'project.pbxproj' | rg 'StetMobile\.xcodeproj'` before building.
- Stable macOS build: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer make build`.
- iOS 27 simulator build: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer /Applications/Xcode-beta.app/Contents/Developer/usr/bin/xcodebuild -project StetMobile-remove-whisper/StetMobile.xcodeproj -scheme StetMobile -sdk iphonesimulator27.0 -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`.
- `StetVisuals/MacDictationAudioReactiveOrb.metal` makes the macOS build depend on the Metal Toolchain matching stable Xcode. Diagnose with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -showComponent MetalToolchain -json`; install with the same `DEVELOPER_DIR` and `xcodebuild -downloadComponent MetalToolchain`. Never substitute the Beta or an older Metal toolchain for the stable build.
- Local state verified on 2026-07-19: Xcode 27 Beta and Metal Toolchain `27A5218h` are installed and functional, while stable Xcode 26.6 expects Metal Toolchain `17F109`, which its Apple component catalog currently fails to install. Recheck component status before attributing a Metal build failure to source code.

## Documentation Entry Points

- Use `README.md` for repository-level setup, local build, and baseline test commands.
- Use [`docs/specs/`](../../docs/specs/index.md) as the source of truth for feature behavior and implementation boundaries.
- Use each feature's `quickstart.md` as the preferred module-level entry point when present.
- Use `docs/release.md` for the detailed release process, environments, signing, notarization, and publishing flow.
- Assume detailed testing, validation, and operation guides may live under `docs/` and should be preferred over duplicating long procedures in this file.
- Keep this root `AGENTS.md` short. Add durable entry points and decision rules here; put long-form workflows and checklists in dedicated docs.

## Editing Rules

- Keep changes scoped to the target feature's `Relevant Source Code` unless the task clearly requires a broader cross-feature edit.
- Prefer small, verifiable patches over speculative refactors or broad architectural cleanup.
- Do not silently introduce behavior that is outside the active spec and Technical Plan; if implementation and docs conflict, call out the conflict before broadening scope.
- Do not add extra fallback paths, defensive branches, or alternative UX flows by default. Only add fallback behavior when the spec, plan, existing architecture, or the task explicitly calls for it.
- Reuse the existing app structure: keep app lifecycle and windowing logic in `StetMac/App/`, core services in `StetMac/Core/`, feature UI and view models in `StetMac/Features/`, and shared types in `StetMac/Shared/`.
- Preserve the current SwiftUI + AppKit integration patterns instead of introducing a parallel UI or state-management approach without a strong reason.
- For UI work, do not add extra buttons, toggles, menus, panels, or settings without an explicit product or spec reason. Prefer the smallest UI change that satisfies the request.
- When changing behavior, update or add tests where practical, starting with the feature's documented `Relevant Tests`.
- If automated coverage is weak for the affected flow, record the manual validation performed or still required.
- Do not run multiple Git commands that write the index in parallel. Commands such as `git add`, `git commit`, `git restore`, and `git cherry-pick` should be executed sequentially to avoid leaving a stale `.git/index.lock`.
- Do not edit `dist/` artifacts, release automation, signing, notarization, Sparkle configuration, dependency versions, or any release scripts unless the task explicitly targets those areas.

## Repository Tree

```text
.
├── AGENTS.md
├── StetMac/               # Main macOS app target sources
│   ├── App/               # App lifecycle, windowing, workflows, platform behavior
│   │   ├── AudioBehavior/
│   │   ├── Lifecycle/
│   │   ├── Windowing/
│   │   └── Workflows/
│   ├── Assets.xcassets/   # App assets
│   ├── Core/              # Core domain and service logic
│   │   ├── AIProviders/
│   │   ├── AppBranch/
│   │   ├── Audio/
│   │   ├── Clipboard/
│   │   ├── DictationPipeline/
│   │   ├── Hotkey/
│   │   ├── Media/
│   │   ├── Rewrite/
│   │   ├── Security/
│   │   ├── Speech/
│   │   ├── TextInput/
│   │   └── Transcribed/
│   ├── Features/          # Feature UI, shells, onboarding flows, view models
│   │   ├── Dictation/
│   │   ├── MacShell/
│   │   └── Onboarding/
│   ├── Resources/         # Bundled resources
│   └── Shared/            # Shared models and utilities
│       ├── Models/
│       └── Utilities/
├── StetMacTests/          # macOS unit and integration tests, mirrors app structure
│   ├── App/
│   ├── Core/
│   ├── Features/
│   └── Support/
├── StetMacUITests/        # macOS UI tests
├── StetVisuals/           # Visual components and shader workbench
├── Stet.xcodeproj/        # Xcode project
├── docs/                  # Human-oriented project docs (release, roadmap)
├── scripts/               # Utility and automation scripts
├── .github/               # CI workflows and GitHub config
└── dist/                  # Build/release artifacts
```

Monorepo harness docs (specs, exec-plans, architecture, validation) live at repository root [`docs/`](../../docs/index.md).

## Spec Workflow

- Before starting feature work, identify the module and the active entry under [`docs/specs/`](../../docs/specs/index.md).
- If the request maps to an active spec, read it before making code changes.
- Read the matching Technical Plan under [`docs/exec-plans/active/`](../../docs/exec-plans/README.md) next for implementation decisions, tradeoffs, and documented deviations.
- Treat Technical Plans as frozen design records for one implementation cycle; current behavior truth is code plus [`docs/ARCHITECTURE.md`](../../docs/ARCHITECTURE.md).
- If the request does not clearly map to an active spec, pause and clarify the target spec or propose the most likely candidate before making broad changes.
- If a request spans multiple features, identify the primary spec and call out affected secondary specs before implementation.
- Do not read [`docs/archive/specs-legacy/`](../../docs/archive/README.md); it is gitignored local history only.
