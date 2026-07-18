# Implementation Plan: Text Output Handling

**Branch**: `006-text-output-handling` | **Date**: 2026-03-27 | **Spec**: [spec.md](./spec.md)  
**Input**: Current implementation, current Constitution, and the legacy `.kiro/specs/text-output-handling/` docs

## Summary

This plan documents the current design of Stet's macOS text output handling flow. The feature delivers recognized text through the existing dictation and rewrite workflows, uses clipboard-backed automatic output, activates the target app before collecting verification metadata, verifies whether paste succeeded through bounded post-paste polling, and falls back to clipboard-preserved recovery when automatic output is unavailable or unverified.

This plan remains grounded in the current implementation, but it now also records the approved scoped design addition needed to align the feature with the updated spec: explicit optimistic delivery for verification-blind target apps. The first implementation pass is intentionally narrow and is limited to a small explicit bundle-identifier set rather than a generic unverifiable-success policy.

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
- This document describes the implementation that exists in the branch; it is not proposing a separate task list or future redesign
- Current implementation takes precedence over the legacy `.kiro` draft when they differ
- `plan.md` must describe design, not a task list
- The approved design delta must stay inside the explicit optimistic-delivery scope defined by `spec.md`
- The first implementation pass must be limited to `com.microsoft.VSCode`, `com.openai.codex`, `com.google.antigravity`, and `dev.zed.Zed`
- No editor extension, no global "verification unavailable means success" rule, and no unrelated output-flow cleanup are in scope

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
StetMac/App/Workflows/
├── MacDictationCaptureCoordinator.swift
├── MacDictationWorkflowController.swift
└── MacAppSessionController.swift

StetMac/App/Lifecycle/
└── MacPermissionManager.swift

StetMac/Core/Clipboard/
├── ClipboardService.swift
└── PasteboardRestoreCoordinator.swift

StetMac/Core/TextInput/
└── TextInjectionService.swift

StetMac/Features/Dictation/
├── DictationAction.swift
├── DictationFailure.swift
├── DictationState.swift
├── DictationView.swift
└── DictationViewModel.swift
```

### Relevant Tests

```text
StetMacTests/App/Workflows/
├── MacDictationCaptureCoordinatorTests.swift
├── MacDictationWorkflowControllerTests.swift
└── MacAppSessionControllerActionTests.swift

StetMacTests/Core/Clipboard/
├── ClipboardServiceTests.swift
└── PasteboardRestoreCoordinatorTests.swift

StetMacTests/Core/TextInput/
└── SystemTextInjectionServiceTests.swift
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

### 6. Paste Verification Is Evaluated Against the Reactivated Target App

The current implementation does not capture the verification baseline from whichever app happens to be frontmost when the workflow finishes. Instead, `TextInjectionService` reactivates the target application, waits briefly for focus to settle, collects the focused-element snapshot, posts the paste event, and then polls focused-element metadata for a bounded interval before deciding whether the paste was verified.

### 7. TextInjectionService Coverage Is Both Direct and Indirect

The current branch now includes a dedicated `SystemTextInjectionServiceTests.swift` file for paste-verification timing and activation ordering, while the workflow and capture coordinator tests continue to exercise the same behavior indirectly through the higher-level output paths.

## Scoped Design Addition

The following design addition is intentionally incremental. It does not replace the current implementation notes above; it defines the smallest approved change needed to eliminate false clipboard-recovery UI in the explicitly profiled editor set without broadening the feature beyond the newly approved spec.

### 1. Product Goal

When Stet posts `Cmd+V` successfully into an explicitly profiled editor such as VS Code, Codex, AntiGravity, or Zed but cannot verify the paste through accessibility metadata, the product should avoid surfacing `clipboardPending` or other failure UI immediately. At the same time, it must avoid silent text loss if the paste did not actually land.

### 2. Design Boundary

- The optimistic-delivery path applies only to explicitly profiled target apps.
- The first implementation pass includes only `com.microsoft.VSCode`, `com.openai.codex`, `com.google.antigravity`, and `dev.zed.Zed`.
- Non-profiled apps keep the current behavior exactly: unverifiable paste remains a failure that preserves text in clipboard and surfaces recovery UI.
- No changes are proposed to rewrite-specific selection replacement semantics beyond the shared output path behavior.

### 3. Output Decision Model

The existing `TextInjectionOutcome` contract remains in place conceptually, but the implementation may classify unverifiable posted-paste results more narrowly. In particular, the workflow can distinguish between a generic `.eventPostedVerificationUnavailable` result and an `.eventPostedVerificationUnavailableInTextInput` result where accessibility still suggests the focused element is a likely text-editing context even though mutation could not be confirmed.

The approved design change happens in the workflow layer:

1. Resolve an internal `TargetAppOutputProfile` from the workflow's `targetApplication` when available.
2. If the workflow has no explicit target app, fall back to the frontmost application observed immediately before the paste attempt.
3. If the resolved profile is `optimisticVerificationBlind` and the injection result is `.eventPostedVerificationUnavailableInTextInput`, treat the output as an optimistic completion rather than a visible failure.
4. If the profile is absent, preserve the current fallback and failure behavior.

This keeps the `TextInjectionService` contract stable while containing app-specific policy in the output workflow.

### 4. Clipboard Recovery Window

The optimistic-delivery path does not introduce a new UI state. Instead, it changes clipboard timing:

- Stet still writes the result into the clipboard before posting `Cmd+V`.
- On the optimistic-delivery path, it does not immediately restore the user's previous clipboard contents.
- Instead, it keeps the delivered text recoverable in clipboard for a short recovery window of 10 seconds.
- After that window, the existing best-effort restore logic runs and restores the original clipboard only if the clipboard has not changed externally.

This is the main mitigation against the false-success risk. If one of the profiled apps failed to accept the paste, the user can still paste manually during the recovery window.

### 5. Component-Level Design

#### `StetMac/Core/TextInput/TextInjectionService.swift`

- Keep the `TextInjectionOutcome` surface small and outcome-oriented rather than pushing app-specific policy into the service.
- Continue bounded verification polling for all apps.
- Continue returning a generic verification-unavailable result when the paste event is posted but the focused-element baseline offers no positive text-input signal.
- Allow the implementation to return a narrower text-input-context verification-unavailable result when the paste event is posted, the focused element still looks editable or text-like, and mutation still cannot be confirmed.
- No app-specific policy should be embedded here.

#### `StetMac/App/Workflows/MacDictationCaptureCoordinator.swift`

- Add the internal target-app profile resolution step before interpreting the paste result.
- Reclassify only the text-input-context verification-unavailable outcome as completed when the resolved target-app profile is optimistic-verification-blind.
- Skip fallback clipboard copy and skip visible failure/panel behavior for that profiled path.
- Request permission remediation only for the existing missing-permission path, not for the profiled optimistic case.

#### `StetMac/Core/Clipboard/PasteboardRestoreCoordinator.swift`

- Extend restore scheduling so the output workflow can request a longer restore delay for the optimistic-delivery path.
- Reuse the existing snapshot-match guard so delayed restoration still avoids overwriting newer clipboard content.

#### `StetMac/App/Workflows/MacAppSessionController.swift`

- No new session or panel states are required.
- The session controller should continue mapping `completed`, `clipboardPending`, and `failed` exactly as it does now.
- The feature change should therefore be expressed by producing `completed` more selectively in the capture coordinator, not by introducing a new panel state.

### 6. Validation Scope

Automated coverage should focus on four behaviors:

- Explicit-profile apps: `.eventPostedVerificationUnavailableInTextInput` resolves to completed and does not surface `clipboardPending`
- Explicit-profile apps: the clipboard result remains recoverable during the 10-second recovery window
- Generic or non-text-input path: `.eventPostedVerificationUnavailable` still falls back to clipboard-preserved recovery
- Clipboard restore path: delayed restore still respects external clipboard changes

Manual validation should confirm the intended UX in the profiled editor set and in a non-profiled app such as TextEdit so the scope boundary is visible in product behavior.

### 7. Risks and Mitigations

- **Risk**: a profiled app paste truly fails and the product does not surface recovery UI.
  **Mitigation**: limit the optimistic path to the explicit editor profile set, require a successfully posted paste event, and keep the transcript recoverable in clipboard for 10 seconds.
- **Risk**: The delayed restore window overwrites newer clipboard data.
  **Mitigation**: retain the existing snapshot-match guard in `PasteboardRestoreCoordinator`.
- **Risk**: The feature expands into a general app-profile system.
  **Mitigation**: keep the first pass to the explicit bundle-identifier set and avoid generalized routing or user-facing configuration.

## Complexity Tracking

No Constitution violations require special justification in this documentation pass.
