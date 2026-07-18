# Implementation Plan: Permission Management

**Branch**: `002-permission-management` | **Date**: 2026-03-27 | **Spec**: [spec.md](./spec.md)  
**Input**: Existing permission-management behavior already implemented in the current codebase, documented without code changes

## Summary

This plan documents the current permission-management design for Stet on macOS. The feature covers two related surfaces: the onboarding permission step and the runtime permission-failure window that appears when a permission-dependent action cannot start.

The goal of this document is not to prescribe a new implementation. It is to describe how the existing code is structured so that `spec.md`, `data-model.md`, and `contracts/` remain aligned with the behavior already present in the branch.

## Technical Context

**Language/Version**: Swift with Swift Concurrency on macOS 26.0+  
**Primary Dependencies**:
- AppKit for settings/system window integration and System Settings navigation
- SwiftUI and Combine for the onboarding permission step and runtime recovery window
- AVFoundation for microphone permission state and microphone access requests
- The app's existing text injection / accessibility service for input control recovery

**Storage**:
- Permission grant state is system-derived and not persisted by this feature
- Onboarding completion is persisted elsewhere in the app and is not itself a permission grant record

**Testing**:
- Swift Testing for session controller behavior and onboarding state transitions
- Manual validation for permission recovery windows and System Settings interactions

**Target Platform**: macOS 26.0+  
**Project Type**: Native desktop application  
**Constraints**:
- This documentation pass must not change code
- Feature docs must reflect the current implementation, not an aspirational permission dashboard
- The runtime recovery surface must stay minimal and separate from onboarding

## Constitution Check

- `spec.md` is written as a product specification focused on user-visible permission behavior.
- `data-model.md` is limited to the feature's domain state, relationships, persistence, and invariants.
- `contracts/` contains only the interfaces that cross module or feature boundaries.
- `plan.md` serves as the feature design document and includes implementation observations.
- `tasks.md` is intentionally omitted in this pass because the current work is documentation alignment rather than execution planning.

## Project Structure

### Documentation

```text
specs/002-permission-management/
├── spec.md
├── plan.md
├── data-model.md
└── contracts/
    ├── MacPermissionsCoordinating.md
    └── MacPermissionGatePresenting.md
```

### Relevant Source Code

```text
StetMac/App/Lifecycle/
├── MacAppContracts.swift
├── MacAppModel.swift
└── MacPermissionManager.swift

StetMac/App/Workflows/
└── MacAppSessionController.swift

StetMac/App/Windowing/
└── MacPermissionGateController.swift

StetMac/Features/Onboarding/
├── OnboardingViewModel.swift
└── Steps/OnboardingPermissionsStep.swift

StetMac/Features/MacShell/PermissionFailure/
├── RuntimePermissionFailureView.swift
└── RuntimePermissionFailureViewModel.swift

StetMac/Core/TextInput/
└── TextInjectionService.swift

StetMac/Core/Speech/
└── MacAudioCaptureService.swift
```

### Relevant Tests

```text
StetMacTests/App/Workflows/
├── MacAppSessionControllerActionTests.swift
└── MacAppSessionControllerSettingsTests.swift

StetMacTests/App/Lifecycle/
└── MacAppPrimitiveTests.swift
```

## Design Overview

### 1. Permission State Is Centralized In The App Coordinator

`MacPermissionManager` derives the current permission state from the system and the existing text-injection service.

It exposes the state needed by both onboarding and runtime recovery:

- microphone status text
- input control / auto-paste status text
- `hasRequiredPermissions`
- a microphone action title that reflects whether the app can request access directly or must open System Settings

This design keeps permission state source-of-truth logic in one place rather than duplicating it across views.

### 2. Onboarding Uses The Same Permission Snapshot

`OnboardingViewModel` consumes `MacPermissionsCoordinating` and drives the onboarding permission step.

The onboarding step:

- shows microphone and input control rows
- exposes recovery actions
- disables Continue until required permissions are available

This is not a separate permission subsystem. It is a UI surface over the same permission state used at runtime.

### 3. Runtime Failures Use A Dedicated Floating Window

`MacAppSessionController` checks permissions before permission-dependent actions and presents the runtime permission-failure gate only when the app is idle and the action cannot proceed.

The runtime gate is implemented by:

- `RuntimePermissionFailureViewModel`
- `RuntimePermissionFailureView`
- `MacPermissionGateController`

The window is intentionally small and focused. It does not attempt to become a general permissions dashboard.

### 4. Permission Refresh Is Event-Driven

The app refreshes permission indicators:

- when it becomes active again
- before permission-dependent actions start
- after the app triggers an explicit permission recovery path

This keeps the permission UI responsive without a separate polling loop.

## Complexity Tracking

No constitution exceptions require justification for this feature. The current implementation already uses the minimal coordination needed for onboarding, runtime recovery, and permission refresh.

## Implementation Observations

The items below record the current implementation as observed in code and tests. They are not requests for code changes in this documentation pass.

### 1. Current Code Uses "Input Control" / "Auto-Paste" Terminology

The old `.kiro` draft uses "text injection" language in several places. The current implementation exposes the same behavior through `autoPaste` / `input control` terminology and the existing text-injection service. The docs here follow the implementation terminology instead of forcing the older wording.

### 2. Project Target Is Newer Than The Old Draft

The old `.kiro` documents describe macOS 12.0+. The current Xcode project target is macOS 26.0, so the compatibility statement in this feature documentation follows the project target rather than the stale draft.

### 3. Runtime Gate Is Real, Not A Stub

`MacPermissionGateController.show(appModel:)` creates a real floating `NSWindow` with a SwiftUI host view and reuses an existing visible window instead of creating duplicates. That behavior is now part of the current implementation.

### 4. The Runtime Gate Stays Out Of Active Capture

`MacAppSessionController` only presents the runtime gate when the app is idle. If recording or processing is already active, the gate is not allowed to interrupt the current session.

### 5. Test Coverage Is Stronger At The Session Layer Than At The Window Layer

The current test suite exercises session-controller permission gating and onboarding permission coordination. The runtime permission window itself is not yet deeply covered by dedicated UI tests, so the visible gate behavior is validated more by integration through the session controller than by direct window tests.
