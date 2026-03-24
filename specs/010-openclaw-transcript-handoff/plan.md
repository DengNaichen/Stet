# Implementation Plan: OpenClaw Transcript Handoff

**Branch**: `010-openclaw-transcript-handoff` | **Date**: 2026-03-23 | **Spec**: [`spec.md`](/Users/nd/Developer/Stet/specs/010-openclaw-transcript-handoff/spec.md)
**Input**: Feature specification from `/specs/010-openclaw-transcript-handoff/spec.md`

**Note**: This plan is written from the local spec/workflow scaffold and the current macOS codebase.

## Summary

Add a second macOS hotkey that reuses the existing capture/capsule flow, but routes the rewritten finalized transcript through the AI path to local OpenClaw instead of injecting text into the focused app. The OpenClaw boundary is the local CLI entrypoint `openclaw agent --message "<rewritten transcript>"`, using default agent resolution only. The existing dictation shortcut stays unchanged, OpenClaw output is not mirrored into the capsule UI, and rewrite failures remain distinct from OpenClaw handoff failures.

## Technical Context

**Language/Version**: Swift 5.0 / macOS 26.0  
**Primary Dependencies**: SwiftUI, AppKit, Combine, Foundation, KeyboardShortcuts, OpenClaw CLI  
**Storage**: UserDefaults + Keychain; no new persistent store  
**Testing**: Swift Testing and XCTest in `apps/mac/StetTests` and `apps/mac/StetUITests`  
**Target Platform**: macOS desktop app  
**Project Type**: desktop-app  
**Performance Goals**: Preserve current hotkey responsiveness and dictation timing; avoid any new visible stall  
**Constraints**: Local-only OpenClaw execution; default agent resolution only; no capsule echo; preserve the existing dictation hotkey path; keep rewrite failure and OpenClaw handoff failure separate  
**Scale/Scope**: One new hotkey route, one additional settings surface, one CLI handoff boundary, and focused test updates in an existing macOS app

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Current working principles for this feature:

- Local-first boundary: OpenClaw is treated as a local CLI dependency, not a remote service.
- Preserve existing route: the current human dictation path and input injection behavior remain unchanged.
- Explicit boundary: `openclaw agent` is the handoff contract; `message send` and gateway RPC are not.
- Small surface area: add a second hotkey and route, do not widen capsule UI responsibilities.
- Separate failure domains: rewrite failures and OpenClaw handoff failures must be distinguishable.
- Testability: route selection, settings wiring, and failure handling must remain unit-testable.

Gate status: PASS

## Project Structure

### Documentation (this feature)

```text
specs/010-openclaw-transcript-handoff/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── openclaw-agent-handoff-contract.md
└── tasks.md
```

### Source Code (repository root)

```text
apps/mac/Stet/
├── App/
│   └── Workflows/
├── Core/
│   ├── AppBranch/
│   ├── DictationPipeline/
│   ├── Hotkey/
│   ├── Rewrite/
│   └── TextInput/
├── Features/
│   └── MacShell/
└── Shared/
    ├── Models/
    └── Utilities/

apps/mac/StetTests/
├── App/
├── Core/
└── Features/

apps/mac/StetUITests/

apps/mac/StetVisuals/
```

**Structure Decision**: Keep the feature inside the existing macOS app target and its companion tests. Likely touch points are `apps/mac/Stet/App/Workflows/MacAppSessionController.swift`, `apps/mac/Stet/Core/Hotkey/HotkeyBindings.swift`, `apps/mac/Stet/Features/MacShell/HotKeySetting/MacHotkeySettingsView.swift`, `apps/mac/Stet/Features/MacShell/HotKeySetting/MacHotKeySettingsSectionView.swift`, and the dictation/rewrite pipeline files under `Core/` and `Features/Dictation/`.

## Complexity Tracking

No constitution violations currently require justification.
