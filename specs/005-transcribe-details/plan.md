# Implementation Plan: BYOK Remote Transcribe and Rewrite Provider Selection on Mac

**Branch**: `005-transcribe-details` | **Date**: 2026-03-23 | **Spec**: [/Users/nd/Developer/Stet/specs/005-transcribe-details/spec.md](/Users/nd/Developer/Stet/specs/005-transcribe-details/spec.md)
**Input**: Feature specification from `/specs/005-transcribe-details/spec.md`

## Summary

Extend the existing macOS BYOK dictation flow from a single-provider configuration to a two-provider configuration:

- one provider selection for transcription
- one provider selection for rewrite

The implementation will preserve the current BYOK two-step runtime shape on Mac:

1. transcribe recorded audio remotely
2. rewrite the transcript remotely

The main work is not in the SDK transport layer. The main work is in settings, snapshot/config modeling, BYOK preflight validation, pipeline wiring, error modeling, and UI/test updates. Managed/relay behavior remains unchanged and out of scope for this feature.

## Technical Context

**Language/Version**: Swift 5, Swift Concurrency, macOS target in Xcode project  
**Primary Dependencies**: SwiftUI, Foundation, third-party `OpenAI` Swift SDK, existing OpenAI-compatible provider integration, UserDefaults, Keychain-backed secret store  
**Storage**: UserDefaults for settings, Keychain for provider API keys, in-memory pipeline state at runtime  
**Testing**: Swift Testing / XCTest-style existing test targets in `apps/mac/StetTests`  
**Target Platform**: macOS desktop app  
**Project Type**: Desktop app with remote AI providers  
**Performance Goals**: Preserve the current BYOK dictation flow latency profile while adding provider selection and preflight checks; do not add unnecessary extra network steps beyond the existing two-step BYOK flow  
**Constraints**: Keep managed/relay behavior unchanged; do not over-abstract the provider model; keep the implementation practical for Swift; keep API keys stored per provider rather than per step  
**Scale/Scope**: Narrow feature slice limited to BYOK dictation cleanup, provider selection, preflight validation, limited naming cleanup, and regression-safe test coverage

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- Constitution file is still an unfilled template, so there are no repo-specific enforceable gates to evaluate.
- This plan keeps complexity bounded by reusing the current OpenAI-compatible SDK transport instead of introducing a new provider abstraction layer.
- This plan preserves existing managed/relay behavior instead of expanding scope into backend or session-driven paths.
- This plan requires regression tests for settings, preflight validation, BYOK pipeline wiring, and existing relay behavior.

**Gate result**: PASS, with the explicit constraint that provider abstraction remains capability-specific rather than fully generalized.

## Project Structure

### Documentation (this feature)

```text
specs/005-transcribe-details/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
└── tasks.md
```

### Source Code (repository root)

```text
apps/mac/Stet/
├── App/Lifecycle/
│   └── MacAppBootstrapper.swift
├── Core/
│   ├── DictationPipeline/
│   │   ├── DictationExecutionRoute.swift
│   │   └── DictationPipelineFactory.swift
│   ├── OpenAI/
│   │   ├── OpenAIConfiguration.swift
│   │   └── OpenAISDKClientFactory.swift
│   ├── Rewrite/
│   │   ├── OpenAIRewriteService.swift
│   │   └── TextRewriteService.swift
│   ├── Speech/
│   │   └── ConfigurableSpeechService.swift
│   └── Transcribed/
│       └── OpenAITranscriptionService.swift
├── Features/
│   ├── Dictation/
│   │   └── DictationFailure.swift
│   ├── MacShell/Openai/
│   │   └── MacOpenAISettingsViewModel.swift
│   └── Onboarding/
│       └── OnboardingViewModel.swift
└── Shared/Utilities/
    ├── DictationSettingsStore.swift
    └── MacPreferences.swift

apps/mac/StetTests/
├── Core/
│   ├── DictationPipeline/DictationPipelineTests.swift
│   └── Speech/ConfigurableSpeechServiceTests.swift
└── Features/
    └── Dictation/DictationViewModelTests.swift
```

**Structure Decision**: Keep the current macOS app structure. Concentrate changes in settings, pipeline wiring, error/UI messaging, and targeted naming cleanup. Do not create a new generalized provider framework.

## Phase 0: Research Conclusions Applied

- Existing experiments already justify a two-step BYOK flow.
- Independent provider selection is required because the best provider choice differs between ASR and rewrite.
- The current OpenAI-compatible SDK stack can continue to serve both OpenAI and Groq.
- Provider API keys are already stored per provider, which reduces migration cost.
- Supported default combinations for this feature are:
  - `OpenAI -> OpenAI`
  - `Groq -> Groq`
  - `Groq -> OpenAI`
- `OpenAI -> Groq` will not receive a first-class default configuration in this feature.

## Implementation Design

### 1. Split settings and snapshot modeling by capability

Replace the current single-provider BYOK model with capability-specific settings:

- `transcriptionProvider`
- `rewriteProvider`

Implementation intent:

- add a new persisted preference for rewrite provider
- keep the existing per-provider keychain storage
- load both provider selections into the snapshot
- load enough configuration data to build distinct transcription and rewrite configs
- default `rewriteProvider` to `transcriptionProvider` so existing users land on a stable single-provider setup

This feature should not store API keys by step. Keys remain stored by provider and are looked up according to the selected step provider.

### 2. Introduce provider-neutral configuration naming without over-abstracting

The current naming implies OpenAI-only ownership even though the code already serves OpenAI and Groq. The feature should correct the misleading configuration-facing naming, but avoid a full protocol-heavy provider framework.

Implementation intent:

- move toward provider-neutral naming at the configuration/settings/pipeline layer
- keep two capability-specific concepts:
  - transcription provider
  - rewrite provider
- do not introduce a single generic provider protocol spanning all AI capabilities
- allow some existing transport-layer `OpenAI*` names to remain if they still clearly represent the OpenAI-compatible SDK adapter layer

This is a limited naming cleanup, not a full repository-wide rename.

### 3. Add BYOK preflight validation before dictation starts

Before building or executing the BYOK pipeline, validate that the selected providers are fully configured.

Validation rules:

- if transcription uses OpenAI, OpenAI key must exist
- if transcription uses Groq, Groq key must exist
- if rewrite uses OpenAI, OpenAI key must exist
- if rewrite uses Groq, Groq key must exist
- if providers differ, both keys must be present

Implementation intent:

- run validation before any remote request starts
- fail before transcription begins
- expose enough structure in the error model to identify both:
  - the blocked step
  - the missing provider key

This step is required to support mixed-provider setups cleanly.

### 4. Rewire the BYOK pipeline to use per-step providers

Keep the current BYOK runtime orchestration shape in `ConfigurableSpeechService`:

1. transcribe audio
2. rewrite transcript

But update pipeline assembly so the two steps can use different providers and different configurations.

Implementation intent:

- keep `ConfigurableSpeechService` as the main orchestration layer
- update `DictationPipelineFactory` and related route/snapshot input so BYOK/direct can create:
  - transcription service configured for the selected transcription provider
  - rewrite service configured for the selected rewrite provider
- keep relay/managed unchanged:
  - relay still provides transcription through relay
  - relay still skips local rewrite on Mac

This feature should rewire inputs, not replace the underlying service implementations.

### 5. Expand the error model and user-facing messaging

Current configuration errors are provider-only. They need to become step-aware for this feature.

Implementation intent:

- upgrade the missing-configuration error path so it can represent:
  - missing transcription provider key
  - missing rewrite provider key
  - mixed-provider setup missing both
- keep configuration failures distinct from runtime failures
- preserve the current Dictation UI flow that shows structured `DictationFailure` values
- update user-facing messages to be action-oriented, for example:
  - `Add an OpenAI API key to use OpenAI for rewrite.`

The UI should not force the user to infer whether the missing key belongs to transcription or rewrite.

### 6. Update settings and onboarding surfaces for dual-provider BYOK

The current settings flow assumes one provider and one visible credential field. This feature needs a dual-provider mental model.

Implementation intent:

- update settings view model behavior so transcription and rewrite provider selections can be edited independently
- ensure the credential UI can still save provider-scoped keys while reflecting the currently selected step providers
- update onboarding or setup flows only as needed to avoid conflicting single-provider assumptions
- keep the UX pragmatic:
  - do not require a complex provider framework UI
  - do clearly show when one or two provider keys are needed

## Test Strategy

### Settings and persistence

- verify save/load for `transcriptionProvider`
- verify save/load for `rewriteProvider`
- verify defaulting behavior:
  - `rewriteProvider` follows `transcriptionProvider` until explicitly changed
- verify per-provider key lookup still works with:
  - same-provider flows
  - mixed-provider flows

### Preflight and error modeling

- verify BYOK preflight fails before execution when transcription key is missing
- verify BYOK preflight fails before execution when rewrite key is missing
- verify mixed-provider setup fails with both missing requirements when both keys are absent
- verify the resulting error identifies:
  - the blocked step
  - the relevant provider

### Pipeline and runtime behavior

- verify supported combinations:
  - `OpenAI -> OpenAI`
  - `Groq -> Groq`
  - `Groq -> OpenAI`
- verify `OpenAI -> Groq` behavior is not silently treated as a supported default combination
- verify transcription success feeds rewrite input
- verify transcription failure prevents rewrite
- verify rewrite failure surfaces as a failed dictation result
- verify final user-visible output is the rewritten text rather than the intermediate transcript

### Regression coverage

- keep existing relay/managed route tests passing without semantic change
- keep existing relay path behavior:
  - relay still skips local rewrite on Mac
- preserve current direct-path rewrite behavior when both selected providers are the same

## Post-Design Constitution Check

- Scope remains bounded to macOS BYOK dictation cleanup.
- No backend implementation is introduced.
- No generalized provider framework is introduced.
- Existing OpenAI-compatible transport is reused.
- Managed/relay remains unchanged.
- Test coverage is required for all new provider combinations and preflight failures.

**Post-design gate result**: PASS.

## Generated Artifacts For This Plan

- `research.md`: completed and aligned with provider/model selection decisions
- `contracts/`: intentionally deferred for now
- `data-model.md`: still to be completed
- `quickstart.md`: still to be completed
- agent context update: still to be run after remaining design artifacts are finalized

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| Capability-specific provider split instead of one shared provider | The feature requires independent provider selection for transcription and rewrite | A single shared provider cannot represent the requested product behavior |
| Limited naming refactor without full repository-wide rename | Product/config naming is currently misleading, but a total rename would expand scope too much | Leaving all naming unchanged would make the dual-provider design harder to understand and maintain |
