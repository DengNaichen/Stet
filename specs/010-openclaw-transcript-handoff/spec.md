# Feature Specification: OpenClaw Transcript Handoff

**Feature Branch**: `010-openclaw-transcript-handoff`  
**Created**: 2026-03-23  
**Status**: Draft  
**Input**: User description: "Add a second hotkey that still opens the capsule, but forwards the finalized transcript to local OpenClaw instead of injecting text into the current input field."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Hand off transcript to OpenClaw via AI route (Priority: P1)

As a user, I can use a second shortcut to capture speech and send the finalized transcript to my local OpenClaw assistant through the AI app branch instead of typing it into the current app.

**Why this priority**: This is the core value of the feature. Without the AI-route handoff, the new shortcut does not solve the intended workflow.

**Independent Test**: Trigger the new shortcut, speak a short sentence, finish dictation, and confirm the text is delivered to OpenClaw rather than injected into the active input field.

**Acceptance Scenarios**:

1. **Given** Stet is running and OpenClaw is available locally, **When** the user triggers the OpenClaw shortcut and completes dictation, **Then** the finalized transcript is forwarded to OpenClaw through the AI route.
2. **Given** the user is typing in another app, **When** the OpenClaw shortcut completes successfully, **Then** the other app is left unchanged and no text is injected into its input field.
3. **Given** the transcript is empty, **When** the user finishes the capture, **Then** Stet does not send an empty payload to OpenClaw.

---

### User Story 2 - Preserve the existing dictation flow (Priority: P2)

As a user, I can continue using the existing dictation shortcut to inject text into the current focused app exactly as before.

**Why this priority**: The new feature must not regress the original workflow. Users need both paths to coexist.

**Independent Test**: Trigger the original dictation shortcut and verify the text still lands in the focused input field.

**Acceptance Scenarios**:

1. **Given** the original dictation shortcut is configured, **When** the user uses it, **Then** the resulting transcript is injected into the current input field as before.
2. **Given** the OpenClaw shortcut is configured, **When** the user uses the original shortcut, **Then** the OpenClaw path is not used.

---

### User Story 3 - Make the OpenClaw route discoverable (Priority: P3)

As a user, I can see and manage the OpenClaw shortcut in settings so I know which shortcut sends text to OpenClaw.

**Why this priority**: The feature needs a clear affordance. Otherwise users cannot tell the two shortcuts apart.

**Independent Test**: Open settings and verify the OpenClaw shortcut is visible, labeled, and can be changed independently of the primary dictation shortcut.

**Acceptance Scenarios**:

1. **Given** settings are open, **When** the user looks at the hotkey section, **Then** the OpenClaw shortcut is clearly labeled.
2. **Given** the user changes the OpenClaw shortcut, **When** they reopen settings, **Then** the new shortcut is persisted.

### Edge Cases

- What happens if the OpenClaw command is missing from `PATH`?
- What happens if OpenClaw is installed but the local gateway/config is not ready?
- What happens if the rewrite pipeline produces no finalized transcript?
- What happens if the dictation result is produced but OpenClaw rejects the handoff?
- What happens if the user triggers the OpenClaw shortcut while another capture is already in progress?
- What happens if the user has rewrite enabled and the final transcript differs from the raw speech text?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST support a second hotkey that uses the same capture and capsule UI flow as the existing dictation shortcut.
- **FR-002**: The system MUST forward the finalized transcript from the second hotkey to local OpenClaw through the AI route instead of injecting text into the currently focused app.
- **FR-003**: The system MUST leave the existing primary dictation shortcut behavior unchanged.
- **FR-004**: The system MUST surface a clear, user-visible failure when the OpenClaw handoff cannot be completed.
- **FR-005**: The system MUST prevent empty or whitespace-only transcripts from being handed off to OpenClaw.
- **FR-006**: The system MUST present the OpenClaw shortcut in settings so users can discover and change it independently.
- **FR-007**: The system MUST preserve the current dictation settings, permissions, and capture lifecycle for both shortcuts.
- **FR-008**: The system MUST treat OpenClaw as an AI destination and MUST NOT route it through the human input-injection path.
- **FR-009**: The system MUST surface a clear, user-visible failure when the existing AI rewrite pipeline does not produce a finalized transcript for the OpenClaw route.
- **FR-010**: The system MUST NOT mirror OpenClaw's response into the capsule; any downstream response handling remains outside the Stet UI surface.

### Key Entities

- **DictationRoute**: The destination for finalized transcript output. For this feature, at minimum, it distinguishes between the existing input-injection path and the OpenClaw handoff path.
- **OpenClawHandoff**: The operation that delivers finalized transcript text to the local OpenClaw assistant.
- **RewriteFailure**: A failure in the existing AI rewrite pipeline before any OpenClaw handoff occurs.
- **HotkeyBinding**: The user-configurable shortcut that selects which route the capture uses.

## Assumptions / Open Questions

- Assumption: Stet will invoke OpenClaw through its local CLI entrypoint, not through a Swift SDK.
- Assumption: The dependency boundary for this feature is `openclaw agent`, which is treated as the AI route.
- Assumption: The feature supports only local OpenClaw execution.
- Assumption: The OpenClaw route uses the rewritten finalized transcript produced by the existing AI pipeline.
- Assumption: Telegram is an internal OpenClaw delivery channel, not a Stet dependency.
- Assumption: The app branch already distinguishes human versus AI destinations, and OpenClaw belongs in the AI branch.
- Assumption: The OpenClaw route uses the default agent resolution and does not pin a named agent id.
- Assumption: OpenClaw responses are not surfaced in the capsule; any delivery surface is owned by OpenClaw.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user can complete an OpenClaw handoff from shortcut press to delivered transcript without text being inserted into the active app.
- **SC-002**: The existing dictation shortcut still injects text into the active app after the feature ships.
- **SC-003**: Users can identify the OpenClaw shortcut in settings without needing documentation.
- **SC-004**: OpenClaw handoff failures are reported clearly enough that a user can tell whether the issue is local availability or message delivery.
- **SC-005**: If rewrite fails before handoff, users receive a distinct failure state that identifies the AI pipeline as the source.
