# AGENTS.md

## Tech Stack

- Language: Swift
- Platform: macOS native app built from `Stet.xcodeproj`
- UI: SwiftUI with AppKit integration for windows, menu bar, permissions, and platform behavior
- Concurrency and state: Swift Concurrency, Combine, and some Observation usage
- Audio and system frameworks: AVFoundation, CoreAudio, ApplicationServices, Metal, MetalKit, OSLog
- Persistence and local state: `UserDefaults`, Keychain-backed secret storage, some SwiftData models
- Networking and provider integrations: URLSession-based services plus OpenAI-compatible and Supabase-backed integrations
- Testing: Swift Testing, plus manual validation for platform-heavy flows
- Package management: Swift Package Manager via Xcode
- Common external packages used across the app include `KeyboardShortcuts`, `Sparkle`, `supabase-swift`, and `OpenAI`; feature-specific dependencies should be confirmed in the relevant source and `plan.md`

## Where To Start

- Project start: begin with this `AGENTS.md`, then locate the relevant feature under `specs/`, and use `Stet/StetApp.swift`, `Stet/App/`, and `Stet/Features/` as the main repository-level entry points.
- Feature start: after identifying the target `specs/<id>-<feature>/` directory, read `quickstart.md` first when present, then `spec.md`, then `plan.md`.
- If a feature's `quickstart.md` is missing or stale, fall back to `plan.md` and use its `Project Structure` section to find the right source files and tests.

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

## Documentation Entry Points

- Use `README.md` for repository-level setup, local build, and baseline test commands.
- Use feature docs under `specs/<id>-<feature>/` as the source of truth for feature behavior and implementation boundaries.
- Use each feature's `quickstart.md` as the preferred module-level entry point when present.
- Use `docs/release.md` for the detailed release process, environments, signing, notarization, and publishing flow.
- Assume detailed testing, validation, and operation guides may live under `docs/` and should be preferred over duplicating long procedures in this file.
- Keep this root `AGENTS.md` short. Add durable entry points and decision rules here; put long-form workflows and checklists in dedicated docs.

## Editing Rules

- Keep changes scoped to the target feature's `Relevant Source Code` unless the task clearly requires a broader cross-feature edit.
- Prefer small, verifiable patches over speculative refactors or broad architectural cleanup.
- Do not silently introduce behavior that is outside the target `spec.md` and `plan.md`; if implementation and docs conflict, call out the conflict before broadening scope.
- Do not add extra fallback paths, defensive branches, or alternative UX flows by default. Only add fallback behavior when the spec, plan, existing architecture, or the task explicitly calls for it.
- Reuse the existing app structure: keep app lifecycle and windowing logic in `Stet/App/`, core services in `Stet/Core/`, feature UI and view models in `Stet/Features/`, and shared types in `Stet/Shared/`.
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
├── Stet/                  # Main app target
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
│   │   ├── Supabase/
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
├── StetTests/             # Unit and integration tests, mirrors app structure
│   ├── App/
│   ├── Core/
│   ├── Features/
│   └── Support/
├── StetUITests/           # UI tests
├── StetVisuals/           # Visual components and shader workbench
├── Stet.xcodeproj/        # Xcode project
├── docs/                  # Human-oriented project docs
├── scripts/               # Utility and automation scripts
├── specs/                 # Feature specs and implementation planning artifacts
│   ├── 001-audio-device-management/
│   ├── 002-permission-management/
│   ├── 003-audio-capture-pipeline/
│   ├── 004-audio-post-processing/
│   ├── 005-transcribe-details/
│   ├── 006-text-output-handling/
│   └── 007-app-branch/
├── .github/               # CI workflows and GitHub config
├── .specify/              # Specification tooling
├── .agents/               # Local agent skills and support files
└── dist/                  # Build/release artifacts
```

## Spec Workflow

- Before starting feature work, first identify which module and which `specs/<id>-<feature>/` directory the request belongs to.
- If the request maps to an existing spec, read `spec.md` before making code changes.
- Read `plan.md` next to understand implementation decisions, tradeoffs, and any documented deviations from older docs or drafts.
- Treat `plan.md` as a structured design document. Across this repository, the stable high-value sections are usually `Summary`, `Technical Context`, `Constitution Check`, `Project Structure`, `Implementation Observations`, and `Complexity Tracking`, with some features also including `Design Overview` or `Design`.
- In `plan.md`, use the `Project Structure` section as the default task boundary. Start from its documented `Relevant Source Code` / `Source Code` and `Relevant Tests` when present before scanning broadly through the repository.
- Expect feature-level variation. Not every plan includes every section, and some plans use slightly different headings such as `Documentation (this feature)`, `Source Code (repository root)`, `Design`, or `Design Overview`.
- If `tasks.md` exists, treat it as the execution checklist, not the source of truth for feature behavior.
- If the request does not clearly map to a spec, pause and clarify the target spec or propose the most likely candidate before making broad changes.
- If a request spans multiple specs, identify the primary spec and call out affected secondary specs before implementation.
