# Implementation Plan: App Branch

**Branch**: `007-app-branch` | **Date**: 2026-03-27 | **Spec**: [`spec.md`](./spec.md)
**Input**: Feature specification from `/specs/007-app-branch/spec.md`

## Summary

Document the actual `app-branch` runtime signal that exists in the current macOS app: a foreground-app monitor, observer callbacks, host-app exclusion, and the derived app-audience classification that downstream cleanup logic uses.

This plan follows the required priority order:

1. Constitution
2. Current implementation
3. Old `.kiro` drafts

Where the old `.kiro` draft conflicts with the current implementation, this plan treats the implementation as the source of truth and records the divergence here instead of trying to retrofit the code to match the older text.

## Technical Context

**Language/Version**: Swift 6 / macOS app target  
**Primary Dependencies**: AppKit, Foundation, Swift Concurrency, Swift Testing  
**Storage**: No persistence for app-branch state; all state is runtime-only  
**Testing**: Swift Testing in `StetTests/Core/AppBranch` plus existing workflow integration tests  
**Target Platform**: macOS desktop app  
**Project Type**: Desktop application feature inside the main app target  
**Performance Goals**: Synchronous `currentApp` access, event-driven updates, and non-blocking observer delivery on a dedicated callback queue  
**Constraints**: Docs only; no code changes; public contract should cover only real cross-module APIs; internal test seams should stay out of `contracts/`  
**Scale/Scope**: One internal runtime feature with a small public surface and a few downstream consumers

## Constitution Check

*GATE: Must pass before design is considered complete.*

- `spec.md` is product-facing and focused on behavior, scope, and measurable outcomes.
- `data-model.md` captures runtime entities, relationships, state transitions, and invariants without drifting into code structure.
- `contracts/` documents only the public API surface that other app modules consume.
- `plan.md` is used as the design doc and includes implementation observations instead of becoming a task list.
- `tasks.md` is intentionally not created in this pass because the user asked for documentation only.

**Gate result**: PASS

## Project Structure

### Documentation (this feature)

```text
specs/007-app-branch/
├── spec.md
├── plan.md
├── data-model.md
└── contracts/
    └── AppBranchMonitor.md
```

### Source Code (repository root)

```text
Stet/
├── App/
│   └── Workflows/
│       └── MacAppSessionController.swift
├── Core/
│   ├── AppBranch/
│   │   ├── AppBranchMonitor.swift
│   │   ├── AppBranchWorkspace.swift
│   │   ├── AppInfo.swift
│   │   └── AppAudience.swift
│   ├── Speech/
│   │   └── ConfigurableSpeechService.swift
│   └── Rewrite/
│       └── TextRewriteService.swift
StetTests/
├── Core/AppBranch/
│   ├── AppBranchMonitor*.swift
│   ├── AppAudienceResolverTests.swift
│   └── AppInfoTests.swift
└── App/Workflows/
    └── MacAppSessionControllerSettingsTests.swift
```

**Structure Decision**: Keep the feature embedded in the main app target under `Stet/Core/AppBranch` and document only the real public surface. The current implementation is not a standalone module even though the old `.kiro` draft described it that way.

## Complexity Tracking

| Area | Why It Exists In The Current Design | Simpler Alternative Rejected By The Current Implementation |
|------|--------------------------------------|------------------------------------------------------------|
| Shared foreground-app monitor | Multiple downstream workflows need the same current-app signal and activation updates | Re-querying AppKit independently in each consumer would duplicate logic and make exclusion behavior inconsistent |
| Previous non-excluded fallback state | Excluding the host app or another bundle requires a stable fallback when the excluded app becomes frontmost | Returning `nil` immediately on every excluded activation would make prompt routing more fragile |
| Heuristic audience classification | Prompt routing needs a lightweight way to distinguish AI-oriented tools from ordinary apps | A manual per-app configuration layer would add product and persistence scope that the current implementation does not carry |

## Implementation Observations

### What the current code actually does

- `AppBranchMonitor` is a shared runtime monitor with injectable workspace and callback queue dependencies for tests.
- `currentApp` is computed on demand from the live workspace snapshot; it is not a cached value.
- `startMonitoring()` registers a workspace observer and delivers an initial snapshot to observers through the callback queue.
- `stopMonitoring()` is idempotent and removes the workspace observation token when one exists.
- `setExcludedBundleID(_:)` updates runtime exclusion state, and the monitor falls back to the previous non-excluded app when the current frontmost app is excluded.
- `AppAudience` is a derived runtime classification that currently steers dictation cleanup behavior through `ConfigurableSpeechService`; the rewrite layer contains audience-aware request shapes, but `app-branch` is not independently wired as a separate rewrite-routing feature.

### Where the old `.kiro` draft diverges

- The old draft described a standalone module; the current implementation is integrated into the main macOS app target.
- The old draft emphasized foreground detection only; the current implementation also classifies apps as human-oriented or AI-oriented for downstream cleanup routing.
- The old draft talked about explicit latency targets; the current implementation is notification-driven and does not encode a hard timing guarantee in code.
- The old draft centered an observer pattern but did not reflect the current fallback behavior where an excluded app can resolve to the previous non-excluded app or `nil`.
- The old draft implied broader interface surfaces than the current code exposes; internal workspace seams remain test-only and should not be documented as public contracts.

### Design Boundaries

- Do not try to force the implementation back to the `.kiro` text.
- Do not expose `AppBranchWorkspaceObserving` as a public contract; it is an internal test seam.
- Do not introduce persistence for the monitor state just to satisfy the old draft.
- Do not turn the plan into a task list; that belongs in `tasks.md` and is intentionally out of scope for this pass.
