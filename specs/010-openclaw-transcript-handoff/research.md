# Research: OpenClaw Transcript Handoff

## Decision 1: Use `openclaw agent --message` as the dependency boundary

Decision: Stet should hand the transcript to OpenClaw by invoking the local CLI entrypoint `openclaw agent --message "<rewritten transcript>"`.

Rationale: The local OpenClaw install exposes `agent` as the direct AI handoff path. `message send` is for delivery channels, and gateway RPC is a lower-level control surface that does not define a stable transcript-handoff contract for Stet.

Alternatives considered:

- `openclaw message send`: rejected because it targets Telegram/Discord/Slack-style delivery channels rather than AI processing.
- `openclaw gateway call`: rejected because it is a control-plane RPC surface, not a stable transcript delivery API.
- Pinning a named agent id: rejected for this feature because the default agent resolution is sufficient and simpler.

## Decision 2: Feed the rewritten finalized transcript into OpenClaw

Decision: The OpenClaw route should receive the rewritten finalized transcript produced by the existing AI pipeline.

Rationale: The repo already has an AI rewrite path with `LocalRewritePromptBuilder` and `TextRewriteRequest` for AI-oriented cleanup. The feature contract is explicitly AI-route only, so the safest behavior is to reuse the existing rewrite result rather than introduce a second rewrite implementation.

Alternatives considered:

- Raw transcript: rejected because it bypasses the existing AI path and conflicts with the feature decision.
- New rewrite step dedicated to OpenClaw: rejected as unnecessary duplication.

## Decision 3: Keep the feature local-only

Decision: The feature should support only local OpenClaw execution.

Rationale: The OpenClaw installation is local, the gateway is configured locally, and the integration boundary is the installed CLI on PATH. This keeps Stet independent from network availability and remote credentials for this route.

Alternatives considered:

- Remote API integration: rejected because the feature is explicitly tied to the local OpenClaw install.
- SDK integration: rejected because OpenClaw is not exposed as a Swift SDK here.

## Decision 4: Do not mirror OpenClaw output into the capsule

Decision: Stet should not mirror OpenClaw responses back into the capsule UI.

Rationale: The feature contract says the capsule is only for capture and route initiation. Any downstream delivery or response handling belongs to OpenClaw-side delivery mechanisms, not to the Stet UI surface.

Alternatives considered:

- Show OpenClaw output in the capsule: rejected because it couples Stet to OpenClaw response shape and delivery timing.
- Treat OpenClaw response as an app-level success banner: rejected for the same reason.

## Decision 5: Split rewrite failure from handoff failure

Decision: Rewrite failure and OpenClaw handoff failure should be distinct error conditions.

Rationale: They happen at different stages and have different recovery actions. If the rewrite pipeline does not produce a finalized transcript, OpenClaw is never called. If the CLI handoff fails, the rewrite already succeeded and the fault is downstream.

Alternatives considered:

- Single generic failure state: rejected because it obscures where the workflow broke.

## Decision 6: Extend the existing hotkey/settings architecture instead of adding a new input system

Decision: Reuse the current hotkey and settings architecture by extending `HotkeyPreference`, `HotkeyBinding`, `KeyboardShortcutsHotkeyRegistrar`, `MacAppSessionController`, and the hotkey settings view.

Rationale: The app already has a single global hotkey pipeline with settings and tests around it. Adding a second route within that system minimizes surface area and preserves the existing primary dictation workflow.

Alternatives considered:

- New global input subsystem: rejected because it would duplicate behavior and increase risk.
- App Intent or Shortcut-based trigger: rejected because the feature is explicitly a second app hotkey, not a system shortcut workflow.

## Decision 7: Reuse the existing app-audience AI branch

Decision: Route the OpenClaw destination through the AI audience branch already modeled in `AppAudience`.

Rationale: The codebase already distinguishes human versus AI destinations and uses different rewrite prompts accordingly. OpenClaw belongs to the AI branch, so the feature should consume the AI rewrite output rather than the human cleanup output.

Alternatives considered:

- Introducing a third audience type: rejected because the feature only needs the existing AI branch.
- Treating OpenClaw as human input injection: rejected by the feature contract.
