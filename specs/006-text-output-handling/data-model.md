# Data Model: Text Output Handling

## Overview

This document describes the domain data and state that drive Stet's macOS text output handling feature. It focuses on the text-delivery workflow, the clipboard fallback state, and the input-injection outcome model rather than framework-specific implementation details.

## Core Entities

### TextOutputRequest

Represents a single completion attempt that needs to deliver text to the user.

**Key Attributes**:

- `text`: The recognized or rewritten text to deliver
- `workflow`: The capture workflow that produced the text, such as dictation or rewrite-from-selection
- `targetApplication`: The application the workflow intends to target
- `retainResultInClipboard`: Whether the workflow expects the text to remain in clipboard after output
- `revealPanelOnFailure`: Whether the UI should surface the panel when output cannot complete

**Invariants**:

- `text` is the exact text produced by the upstream workflow.
- The request does not normalize or reformat the text.

### TextOutputResult

Represents the resolved outcome of a text-output attempt.

**States**:

- `completed`: The text was delivered successfully or intentionally copied for later manual use
- `clipboardPending(text)`: The text is preserved in clipboard for manual copy or recovery
- `failed(failure)`: The output could not complete and surfaced a specific failure

**Important Behavior**:

- `completed` means the workflow no longer needs to keep the capture result in an active pending state.
- For automatic output, `completed` means the input-injection layer observed a verifiable mutation within its bounded post-paste verification window.
- `clipboardPending(text)` keeps the text available without claiming the output succeeded.

### TextInjectionAccessState

Represents the system's ability to simulate input into the target application.

**Key Attributes**:

- `hasAccessibilityAccess`
- `hasPostEventAccess`
- `canSimulateInput`

**Important Behavior**:

- `canSimulateInput` is derived from the underlying system permissions.
- The feature does not store this state; it is evaluated from the OS at runtime.

### TargetAppOutputProfile

Represents explicit output-handling rules for a target app whose paste behavior is not reliably verified through the generic metadata path.

**Key Attributes**:

- `bundleIdentifier`: The app identity used to resolve the profile
- `mode`: The output behavior to apply for that app
- `recoveryWindow`: The clipboard recovery delay to use when the profile is optimistic

**Important Behavior**:

- Only explicitly profiled apps use optimistic-delivery handling.
- The profile is resolved at runtime from the target app or the observed frontmost app.

### ClipboardSnapshot

Represents the clipboard state captured before a temporary override is used for automatic output.

**Key Attributes**:

- `contents`: The clipboard payload before temporary override
- `isOpaque`: Whether the snapshot is treated as best-effort recovery data rather than a durable app-owned record

**Important Behavior**:

- The snapshot exists only to support best-effort restoration after automatic output.

### TextOutputFailure

Represents the user-visible failure categories the output pipeline can emit.

**States**:

- `clipboardWriteFailed`
- `autoPastePermissionMissing`
- `pasteVerificationUnavailable`
- `pasteVerificationFailed`

**Important Behavior**:

- Failure states preserve the distinction between write failure, permission failure, and verification failure.
- Some failures preserve the recovered text in clipboard; others do not.

## Relationships

- `MacDictationWorkflowController` produces `TextOutputRequest`-like inputs for the output pipeline and consumes `TextOutputResult`.
- `ClipboardService` writes the textual payload that the workflow wants to preserve or deliver.
- `TextInjectionService` uses `TextInjectionAccessState` to decide whether the system can attempt input simulation, reactivates the target app before taking its verification baseline, and classifies paste success or failure after a bounded metadata-polling window.
- The injection outcome model may distinguish between a fully opaque verification miss and a likely text-input context that still remained unverifiable, so the workflow can keep optimistic-delivery heuristics narrow.
- `MacDictationCaptureCoordinator` resolves a `TargetAppOutputProfile` before interpreting paste outcomes so explicit optimistic-delivery handling stays outside the generic injection service.
- `PasteboardRestoreCoordinator` keeps a best-effort `ClipboardSnapshot` so temporary overrides can be restored after a successful injection.
- `MacAppSessionController` turns `TextOutputResult` into the visible dictation panel state.

## State Transitions

### Output Flow

```text
pending text
  -> target app activated
  -> pre-paste focus snapshot
  -> attempt clipboard write
  -> attempt text injection
  -> bounded verification polling
  -> completed

pending text
  -> target app activated
  -> pre-paste focus snapshot
  -> clipboard write succeeds
  -> injection unavailable or unverified
  -> clipboard-pending or failure state with recovered text preserved

pending text
  -> empty or whitespace-only
  -> no-op / empty-transcription failure
```

### Clipboard Restore Flow

```text
snapshot captured
  -> temporary clipboard override
  -> successful paste
  -> delayed restore attempt
  -> original clipboard restored if the clipboard has not changed externally

snapshot captured
  -> temporary clipboard override
  -> paste failure
  -> immediate restore attempt
```

### UI Result Flow

```text
result -> completed
result -> clipboardPending(text)
result -> error(failure)
clipboardPending(text) -> idle after manual dismissal or copy
```

## Persistence Model

Persisted data in the current implementation is intentionally small:

- No new durable app-owned storage is introduced by this feature
- Clipboard contents remain system-managed state
- Permission state remains system-managed state
- Any legacy output defaults are migration data elsewhere in the app, not part of this feature's durable model

## Invariants

- The feature preserves the original text content and formatting as produced by upstream transcription or rewrite logic.
- A failure that preserves text in clipboard must leave that text recoverable for the user.
- Only one output result is active for a completed workflow attempt.
- Empty or whitespace-only text does not trigger clipboard writes or input injection.
- Best-effort clipboard restoration must not overwrite a newer clipboard update from another app or user action.

## Out Of Scope For This Data Model

The following are implementation details rather than feature data model concerns:

- exact pasteboard item encoding
- transient pasteboard markers and source tags
- retry timing and delay constants
- focus snapshot comparison mechanics
- low-level accessibility and event-posting APIs
