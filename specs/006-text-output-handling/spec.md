# Feature Specification: Text Output Handling

**Feature Branch**: `006-text-output-handling`  
**Created**: 2026-03-27  
**Status**: Draft  
**Input**: Current implementation, current Constitution, and the legacy `.kiro/specs/text-output-handling/` docs

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Deliver completed text into the target app (Priority: P1)

As a user, when dictation or rewrite completes, I want the resulting text delivered into the intended target app so I do not need to paste manually.

**Why this priority**: This is the primary value of the output pipeline. If this does not work, the feature does not deliver the captured text to the user.

**Independent Test**: Complete a dictation or rewrite workflow in a text field and verify the output lands in the target app without manual paste.

**Acceptance Scenarios**:

1. **Given** a supported target app is captured for the workflow, **When** the text output flow completes successfully, **Then** the text appears in that target app and the workflow completes.
2. **Given** the output flow can verify the paste, **When** the paste succeeds, **Then** the system treats the output as completed rather than pending.
3. **Given** the target app updates its focus metadata slightly after the paste event is posted, **When** the bounded verification window still observes the mutation, **Then** the system treats the output as completed rather than falling back to clipboard-pending recovery.

---

### User Story 2 - Avoid false recovery UI in verification-blind apps (Priority: P1)

As a user, when I dictate into a target app that accepts paste input but does not reliably expose verifiable focus metadata, I want Stet to avoid interrupting me with clipboard recovery UI if the paste likely already succeeded.

**Why this priority**: False failure UI breaks trust in the product during common editor workflows and creates unnecessary recovery friction even when delivery likely succeeded.

**Independent Test**: Complete automatic output in a profiled target app with unreliable verification metadata and verify that successful paste posting does not surface clipboard-pending UI while the text remains briefly recoverable.

**Acceptance Scenarios**:

1. **Given** the target app is on an explicit optimistic-delivery profile because it frequently accepts paste input without exposing verifiable focus metadata, **When** Stet posts the paste command successfully and no contradictory failure signal is observed, **Then** Stet treats the output as completed rather than immediately surfacing clipboard-pending UI.
2. **Given** Stet resolves output through this optimistic-delivery path, **When** the user manually pastes within the short recovery window, **Then** the delivered text is still available from clipboard.
3. **Given** the short recovery window expires without external clipboard changes, **When** the restore attempt runs, **Then** the user's prior clipboard content is restored on a best-effort basis.

---

### User Story 3 - Preserve text when automatic output cannot complete (Priority: P1)

As a user, when the system cannot complete automatic text injection, I want the text preserved in clipboard so I can recover it without re-dictating.

**Why this priority**: Fallback safety is the main reliability guarantee of the feature. The text must not be lost when automatic injection is unavailable or unverified.

**Independent Test**: Simulate missing input-control permissions or failed paste verification and verify the text remains available in clipboard.

**Acceptance Scenarios**:

1. **Given** automatic text injection is unavailable because required permissions are missing, **When** the workflow completes, **Then** the text remains in clipboard and the workflow surfaces a permission-related failure.
2. **Given** the system cannot verify that the paste succeeded in a target app that is not on an optimistic-delivery profile, **When** output is handled, **Then** the text remains in clipboard and the workflow surfaces a distinct verification failure.

---

### User Story 4 - Replace selected text during rewrite workflows (Priority: P2)

As a user, when I rewrite selected text, I want the selection replaced with the rewritten result so I can keep editing in place.

**Why this priority**: Rewrite-from-selection is an important workflow, but it is narrower than the main dictation output path.

**Independent Test**: Select text in a supported target app, trigger rewrite, and verify the selection is replaced or the rewritten text is preserved in clipboard on failure.

**Acceptance Scenarios**:

1. **Given** the target app exposes a replaceable selection, **When** the rewrite output completes successfully, **Then** the selected text is replaced with the rewritten result.
2. **Given** the replacement flow cannot complete, **When** the workflow handles the failure, **Then** the rewritten text remains available in clipboard and the workflow surfaces an appropriate output failure.

---

### User Story 5 - Restore the original clipboard after temporary output (Priority: P2)

As a user, when the system uses clipboard as a temporary bridge for automatic output, I want my previous clipboard content restored on success.

**Why this priority**: Clipboard protection keeps automatic output from destroying unrelated clipboard work.

**Independent Test**: Seed the clipboard with known content, complete an auto-output flow successfully, and verify the original clipboard content is restored on a best-effort basis.

**Acceptance Scenarios**:

1. **Given** the clipboard already contains user content, **When** automatic output succeeds, **Then** the original clipboard content is restored after the temporary paste path completes.
2. **Given** the clipboard changes externally before the scheduled restore runs, **When** the restore attempt occurs, **Then** the newer clipboard content is not overwritten.

---

### User Story 6 - Ignore empty output (Priority: P3)

As a user, when transcription produces no usable text, I want the system to avoid pointless clipboard or paste activity.

**Why this priority**: This is an important guardrail, but it only applies when the capture result is empty.

**Independent Test**: Send whitespace-only text through the output pipeline and verify that no clipboard write or paste attempt occurs.

**Acceptance Scenarios**:

1. **Given** the output text is empty or whitespace only, **When** the workflow completes, **Then** the system performs no output side effects and reports the empty-text failure state where applicable.

### Edge Cases

- What happens when automatic text injection is unavailable because the system lacks input-control permissions?
- What happens when the target app's focus metadata updates slightly after the paste event is posted?
- What happens when the target app does not expose enough focus metadata to verify a paste?
- What happens when the target app is explicitly profiled for optimistic delivery because it frequently accepts paste input without exposing verifiable focus metadata?
- What happens when clipboard writing fails during the fallback path?
- What happens when the clipboard changes externally before a delayed restore runs?
- What happens when optimistic delivery appears successful but the user immediately needs the text again?
- What happens when rewrite output is empty or whitespace only?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST deliver completed dictation and rewrite text through the current output workflow without requiring manual paste when automatic output is enabled by the workflow.
- **FR-002**: The system MUST attempt text injection into the workflow target app, MUST verify against the reactivated target app's available focus metadata within a bounded post-paste window, and MUST treat the result as unconfirmed unless that metadata indicates success.
- **FR-003**: The system MUST preserve the text in clipboard when automatic text injection cannot proceed because required permissions are missing.
- **FR-004**: The system MUST preserve the text in clipboard when injection fails or cannot be verified in a target app that is not explicitly profiled for optimistic delivery, and MUST surface a distinct output failure state for that condition.
- **FR-005**: The system MUST use best-effort clipboard restoration when automatic output temporarily overrides clipboard contents.
- **FR-006**: The system MUST support rewrite-from-selection flows by replacing the selected text when possible and preserving the rewritten text in clipboard when the workflow requires fallback recovery.
- **FR-007**: The system MUST treat empty or whitespace-only output text as a no-op and MUST not write it to clipboard or inject it into the target app.
- **FR-008**: The system MUST preserve the source text content and formatting as provided by the transcription or rewrite result.
- **FR-009**: The system MUST expose distinguishable output states for completed output, clipboard-pending output, and output failures.
- **FR-010**: The system MUST surface clipboard-write failure, permission failure, and paste-verification failure as separate failure conditions.
- **FR-011**: The system MUST support an explicit target-app profile for apps that frequently accept paste input without exposing reliable verification metadata.
- **FR-012**: For target apps on that optimistic-delivery profile, if the paste command is posted successfully and no contradictory failure signal is observed, the system MUST resolve output as completed rather than immediately surfacing clipboard-pending UI.
- **FR-013**: In that optimistic-delivery path, the system MUST keep the delivered text recoverable from clipboard for a short recovery window before attempting clipboard restoration.
- **FR-014**: The system MUST limit optimistic delivery behavior to explicitly profiled target apps and MUST NOT apply it to generic unverified paste outcomes.

### Key Entities *(include if feature involves data)*

- **TextOutputRequest**: Represents the text, workflow context, target application, and output recovery intent for a single completion.
- **TextOutputResult**: Represents the resolved outcome of a completion attempt, including completed, clipboard-pending, and failed states.
- **TextInjectionAccessState**: Represents the current ability to simulate input through accessibility and post-event access.
- **ClipboardSnapshot**: Represents the clipboard state captured before a temporary override so it can be restored best effort later.
- **TextOutputFailure**: Represents the user-visible output failure categories that the UI can distinguish.
- **TargetAppOutputProfile**: Represents product-defined output handling rules for target apps whose paste behavior cannot be evaluated reliably through the generic verification path.
- **OutputRecoveryWindow**: Represents the short interval during which optimistic-delivery text remains recoverable from clipboard before clipboard restoration is attempted.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In successful completion flows, users can see the resulting text appear in the intended target app without manual paste.
- **SC-002**: When injection is unavailable or unverified, the text remains recoverable from clipboard and does not need to be re-dictated.
- **SC-003**: Temporary clipboard override flows restore prior clipboard content on success without overwriting a newer external clipboard update.
- **SC-004**: Empty or whitespace-only output produces zero clipboard writes and zero injection attempts.
- **SC-005**: The UI can distinguish permission failures, clipboard-write failures, and paste-verification failures from each other.
- **SC-006**: In target apps on the optimistic-delivery profile, automatic output no longer surfaces clipboard-pending UI solely because verification metadata is unavailable, while the delivered text remains manually recoverable during the short recovery window.

## Assumptions

- This feature is part of the macOS dictation and rewrite workflows, not a user-selectable routing mode.
- The current branch behavior takes priority over the legacy `.kiro` text-output draft when the two differ.
- Legacy `mac.copyToClipboardOnCapture`, `mac.autoPasteOnCapture`, and `mac.revealPanelOnCapture` keys are migration artifacts, not current user-facing controls in this branch.
- The workflow may request or open system input-control permissions, but permission grant decisions remain controlled by the operating system.
- The target application is the app captured by the workflow, not a separate user-selected destination model.
- Some editor-style target apps, including VS Code, may require an explicit optimistic-delivery profile because their accessibility metadata is insufficient for reliable generic paste verification.
