# OpenClaw Agent Handoff Contract

**Feature**: `010-openclaw-transcript-handoff`  
**Spec**: [`spec.md`](/Users/nd/Developer/Stet/specs/010-openclaw-transcript-handoff/spec.md)  
**Status**: Draft

## Purpose

This contract defines the boundary between Stet and the local OpenClaw assistant for the OpenClaw shortcut path.

The contract is intentionally narrow:

- Stet sends a finalized transcript to OpenClaw as an AI handoff.
- Stet does not inject that transcript into the currently focused application.
- Stet does not depend on OpenClaw's Telegram delivery path.
- Stet does not use OpenClaw gateway RPC as the primary handoff boundary.
- Stet only supports local OpenClaw execution.
- Stet does not mirror OpenClaw's response into the capsule.

## Scope

In scope:

- The command shape Stet uses to hand off text to OpenClaw.
- The minimum input/output expectations for that handoff.
- The failure modes Stet must surface to the user.
- The local configuration assumptions required for the integration.

Out of scope:

- OpenClaw internal agent orchestration.
- Telegram routing details inside OpenClaw.
- The human input-injection path used by the existing dictation shortcut.
- Any future callback or reverse-sync behavior from OpenClaw back into Stet.

## Dependency Model

Stet treats OpenClaw as a local external AI service that is reachable through the installed `openclaw` CLI.

Contractual dependency boundary:

- **Primary boundary**: `openclaw agent`
- **Non-boundary**: `openclaw message send`
- **Non-boundary**: `openclaw gateway call`

Rationale:

- `openclaw agent` is the documented direct AI entrypoint.
- `openclaw message send` targets delivery channels such as Telegram, Discord, or Slack.
- `openclaw gateway call` is a lower-level control-plane/RPC surface and does not define a stable transcript handoff contract for Stet.

## Invocation Path

Stet should hand off the transcript by invoking the local CLI in the form:

```bash
openclaw agent --message "<finalized transcript>"
```

The contract guarantees only the following about invocation:

- The transcript is passed as a single text payload.
- The payload is non-empty after trimming whitespace.
- The payload is delivered through the AI route, not through human input injection.

The contract uses OpenClaw's default agent resolution.
Stet does not pin a specific agent id for this feature.

## Input Contract

### Required Input

- A finalized transcript string.

### Validation Rules

- The transcript MUST contain at least one non-whitespace character.
- The transcript MUST be normalized to the finalized text selected by the feature policy.
- The transcript MUST NOT be emitted into the active app as keyboard input.

### Source Policy

The transcript handed to OpenClaw MUST be the rewritten finalized transcript produced by the existing AI pipeline.

This contract does not require Stet to invent a new rewrite step for OpenClaw.
It only requires Stet to reuse the existing AI path and forward the already-rewritten finalized text.

## Output Contract

The minimum successful handoff contract is:

- The OpenClaw CLI accepts the transcript.
- Stet receives a successful completion signal from the CLI process.
- Stet does not inject the transcript into the active input field.

The contract does not require Stet to parse OpenClaw's conversational response at this stage.
If the implementation later wants to expose OpenClaw output, that behavior must be owned by OpenClaw's delivery channel such as Telegram rather than by the Stet capsule UI.

Observed OpenClaw output characteristics from the local installation:

- Standard text output may contain the assistant response.
- Media references may appear as `MEDIA:<url>` lines.
- A structured JSON mode exists, but this contract does not depend on a specific JSON schema.

## Error Contract

Stet must surface a clear user-visible failure when the handoff cannot be completed.

Minimum expected failure classes:

- `openclaw` CLI not found or not executable.
- OpenClaw is installed but the local runtime/configuration is not ready.
- The handoff payload is empty or whitespace-only.
- The command returns a fatal error instead of a successful completion.
- The upstream AI rewrite pipeline fails before a finalized transcript is available.

Important operational note:

- If the OpenClaw gateway is temporarily unavailable, OpenClaw may fall back to its embedded local runtime.
- Stet should treat that as an implementation detail of OpenClaw, not as a separate dependency path.

## Configuration Requirements

The following local conditions must be true for the handoff to work reliably:

- `openclaw` is available on `PATH`.
- The user has a valid local OpenClaw installation.
- OpenClaw can resolve its local state/config directory.
- The local OpenClaw environment is able to accept an `agent` run.
- The local OpenClaw environment resolves the default agent successfully.
- The existing AI rewrite path has already produced a finalized transcript before this contract begins.

From the current local installation, the following are relevant assumptions:

- OpenClaw runs with a local gateway configuration.
- Telegram is enabled in OpenClaw, but that is not a Stet dependency.
- The Telegram allowlist/group-policy state is an OpenClaw concern, not a Stet contract requirement.
- This contract does not require Stet to configure or discover any named OpenClaw agent id.

## Security and Permissions

- The integration should stay local-only.
- Stet should not require remote credentials for the handoff path.
- Stet should not depend on the user configuring Telegram as a prerequisite for this feature.

## Open Questions

- Should Stet wait for OpenClaw's final reply, or treat the command as fire-and-forget once accepted?

## Acceptance Criteria

- A user can trigger the OpenClaw shortcut and hand off a finalized transcript without typing into the focused app.
- The transcript delivered to OpenClaw is the rewritten finalized transcript from the AI path.
- OpenClaw output is not mirrored into the Stet capsule UI.
- A whitespace-only transcript is rejected before any handoff occurs.
- A missing or misconfigured OpenClaw installation produces a clear failure state in Stet.
- The existing dictation shortcut remains unchanged and continues to inject text into the focused app.
- The contract makes OpenClaw's AI route the only supported boundary for this feature.
