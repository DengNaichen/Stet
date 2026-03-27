# Implementation Plan: Text Output Handling

**Branch**: `006-text-output-handling` | **Date**: 2026-03-27 | **Spec**: [spec.md](./spec.md)  
**Input**: Current implementation, current Constitution, and the legacy `.kiro/specs/text-output-handling/` docs

## Summary

This plan documents the current design of Stet's macOS text output handling flow. The feature delivers recognized text through the existing dictation and rewrite workflows, uses clipboard-backed automatic output, verifies whether paste succeeded, and falls back to clipboard-preserved recovery when automatic output is unavailable or unverified.

This is a documentation pass, not an implementation pass. The purpose of the plan is to explain how the current codebase is structured so that `spec.md`, `data-model.md`, and `contracts/` stay aligned with the implementation that currently ships in this branch.

## Technical Context

**Language/Version**: Swift with Swift Concurrency on macOS  
**Primary Dependencies**:
- AppKit for clipboard and application focus integration
- ApplicationServices for accessibility and input injection APIs
- Foundation for state, timing, and data handling
- SwiftUI and Combine for panel state propagation and user-visible state

**Storage**:
- No new durable storage is introduced by this feature
- Existing clipboard state and permission state are system-managed

**Testing**:
- Swift Testing for workflow coordination, clipboard handling, text injection, and panel state
- Manual validation for system permissions and target-app interaction flows

**Target Platform**: macOS  
**Project Type**: Native desktop application  
**Performance Goals**: Output should feel immediate to the user, and clipboard restoration should remain best effort without blocking the main interaction flow  
**Constraints**:
- Documentation must reflect the current implementation exactly
- No code changes are part of this documentation pass
- Current implementation takes precedence over the legacy `.kiro` draft when they differ
- `plan.md` must describe design, not a task list

## Constitution Check

This feature's documentation follows the current Constitution structure:

- `spec.md` is treated as a product specification focused on user-visible behavior.
- `data-model.md` is limited to the domain entities, relationships, state transitions, and persistence concepts that matter to the feature.
- `contracts/` is limited to interfaces consumed across feature or module boundaries.
- `plan.md` is used as the feature's design document.
- `tasks.md` is intentionally omitted in this pass because the current work is documentation alignment rather than execution planning.

## Project Structure

### Documentation

```text
specs/006-text-output-handling/
├── spec.md
├── plan.md
├── data-model.md
└── contracts/
    ├── ClipboardService.md
    └── TextInjectionService.md
```

### Relevant Source Code

```text
Stet/App/Workflows/
├── MacDictationCaptureCoordinator.swift
├── MacDictationWorkflowController.swift
└── MacAppSessionController.swift

Stet/App/Lifecycle/
└── MacPermissionManager.swift

Stet/Core/Clipboard/
├── ClipboardService.swift
└── PasteboardRestoreCoordinator.swift

Stet/Core/TextInput/
└── TextInjectionService.swift

Stet/Features/Dictation/
├── DictationAction.swift
├── DictationFailure.swift
├── DictationState.swift
├── DictationView.swift
└── DictationViewModel.swift
```

### Relevant Tests

```text
StetTests/App/Workflows/
├── MacDictationCaptureCoordinatorTests.swift
├── MacDictationWorkflowControllerTests.swift
└── MacAppSessionControllerActionTests.swift

StetTests/Core/Clipboard/
├── ClipboardServiceTests.swift
└── PasteboardRestoreCoordinatorTests.swift
```

**Structure Decision**: The documentation for this feature lives entirely under `specs/006-text-output-handling/`, and the source references are the existing workflow, clipboard, input-injection, and UI-state files that already implement the feature.

## Implementation Observations

The items below are observations about the current implementation. They are not requests for code changes in this documentation pass.

### 1. The Implementation Does Not Pre-Detect an Active Input Field

The current code does not follow the older `.kiro` assumption that the system should first detect an active input field and then choose a routing mode. Instead, it attempts output through the current workflow target and verifies the result after the fact. That means the implementation is best described as optimistic output with verification, not upfront mode detection.

### 2. Clipboard Preservation Is Part of the Recovery Path, Not a Separate User Mode

When automatic output cannot proceed or cannot be verified, the implementation preserves the text in clipboard and surfaces a `clipboardPending` or failure state. The recovery path is explicit and user-visible; it is not hidden as an internal success case.

### 3. Legacy Output Preference Keys Are Not Active Product Controls Here

The bootstrap layer still carries legacy keys such as `mac.copyToClipboardOnCapture`, `mac.autoPasteOnCapture`, and `mac.revealPanelOnCapture`, but the current output workflow does not treat them as active feature controls. The running workflow uses its own hard-coded output strategy.

### 4. Dictation and Selection-Rewrite Use the Same Output Services but Not the Same Recovery Behavior

Dictation completion and rewrite-from-selection both flow through the same clipboard and text-injection services, but rewrite-from-selection preserves or restores the selected text differently because the workflow is replacing already-selected content.

### 5. Output Failures Are Classified Deliberately

The current implementation distinguishes clipboard write failure, missing input-control permission, paste-verification unavailable, and paste-verification failed. That classification is important to preserve in the docs because the UI can show different recovery guidance depending on which branch occurred.

### 6. TextInjectionService Coverage Is Indirect

The current branch does not include a dedicated `TextInjectionService` test file. Its behavior is exercised indirectly through the workflow and capture coordinator tests, so the documentation should avoid claiming a deeper unit-test coverage level than the repository currently provides.

## Complexity Tracking

No Constitution violations require special justification in this documentation pass.
