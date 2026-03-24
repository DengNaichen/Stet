# Data Model: OpenClaw Transcript Handoff

## Entities

### HotkeyPreference

Represents a user-configurable shortcut category.

Fields:
- `id: String`
- `title: String`

Expected change:
- Add a second preference for the OpenClaw route.

Validation rules:
- Each hotkey preference id must be unique.
- The title should clearly distinguish the dictation route from the OpenClaw route.

### HotkeyBinding

Represents a named keyboard shortcut bound to a `HotkeyPreference`.

Fields:
- `preference: HotkeyPreference`
- `name: KeyboardShortcuts.Name`

Relationships:
- One `HotkeyBinding` maps to one recorder in settings.
- One binding maps to one hotkey handler registration path.

Validation rules:
- The KeyboardShortcuts name must remain unique per route.
- The OpenClaw binding must not reuse the dictation name.

### DictationRoute

Represents the output destination for the finalized transcript.

Conceptual cases:
- `humanInjection`
- `openClawAI`

Fields:
- Route kind
- Transcript delivery mode
- Whether the route expects the existing AI rewrite output

Relationships:
- Selected by the hotkey that started the capture.
- Consumed by `MacAppSessionController` and the workflow controller after transcription completes.

Validation rules:
- The OpenClaw route must use the AI branch.
- The human route must continue to use text injection.

### RewrittenTranscript

Represents the finalized text produced by the existing AI rewrite pipeline.

Fields:
- `text: String`
- `source: String` or route metadata if needed for diagnostics

Validation rules:
- Must contain at least one non-whitespace character.
- Must already be normalized by the existing rewrite logic before OpenClaw handoff.

### OpenClawHandoff

Represents the act of handing the rewritten transcript to local OpenClaw.

Fields:
- `message: String`
- `command: String` conceptually `openclaw agent --message`
- `usesDefaultAgentResolution: Bool`
- `localOnly: Bool`

Relationships:
- Consumes `RewrittenTranscript`.
- Produces success/failure feedback for the UI workflow.

Validation rules:
- The message must be the rewritten finalized transcript.
- The route must not pin a named agent id for this feature.
- The route must not depend on capsule response mirroring.

### RewriteFailure

Represents failure in the existing AI rewrite pipeline before OpenClaw is called.

Fields:
- `message: String`
- `sourceStage: String` or similar diagnostics

Validation rules:
- If this entity exists, OpenClaw handoff must not run.

### OpenClawHandoffFailure

Represents failure while invoking or completing the local OpenClaw CLI handoff.

Fields:
- `message: String`
- `exitCondition` or `statusText`

Validation rules:
- Must be distinct from rewrite failure.
- Must be surfaced to the user as a separate local failure condition.

## State Transitions

### Primary dictation route

`idle -> starting -> listening -> processing -> result/clipboardPending`

### OpenClaw route

`idle -> starting -> listening -> processing -> rewrittenTranscript -> OpenClawHandoff -> completed/error`

Notes:
- The OpenClaw route reuses the same capture lifecycle as the existing dictation flow.
- The difference is in the post-processing target after the transcript is finalized.
- OpenClaw response handling is not surfaced in the capsule UI.

## Persistence

No new persistent store is required.

Existing preferences are enough:
- UserDefaults for hotkey and rewrite toggles
- Keychain for existing API keys

The OpenClaw route should be driven by new preference keys and existing runtime state, not by a new database/file model.
