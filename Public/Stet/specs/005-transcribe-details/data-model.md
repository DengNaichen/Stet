# Data Model: BYOK Remote Transcribe and Rewrite Provider Selection on Mac

## Overview

This feature extends the existing macOS BYOK dictation model from a single provider choice to a two-step provider model:

- one provider for transcription
- one provider for rewrite

The data model remains Mac-side only. It does not define backend entities.

## Core Entities

### 1. Transcription Provider Selection

Represents the provider selected for the ASR step of the BYOK dictation flow.

**Allowed values**

- `openAI`
- `groq`

**Responsibilities**

- Determines which provider-specific API key is required for transcription.
- Determines which default transcription model should be used.
- Determines which provider-specific configuration is used to build the transcription service.

**Validation rules**

- Must always be present in BYOK mode.
- Must map to a provider-supported default transcription model.
- Must have a matching provider API key before dictation starts.

**Relationships**

- Paired with `Rewrite Provider Selection`.
- Used to derive `Transcription Configuration`.
- Participates in `Provider Configuration Validation`.

---

### 2. Rewrite Provider Selection

Represents the provider selected for the rewrite step of the BYOK dictation cleanup flow.

**Allowed values**

- `openAI`
- `groq`

**Responsibilities**

- Determines which provider-specific API key is required for rewrite.
- Determines which default rewrite model should be used.
- Determines which provider-specific configuration is used to build the rewrite service.

**Validation rules**

- Must always be present when rewrite is enabled in BYOK mode.
- Must map to a provider-supported default rewrite model.
- Must have a matching provider API key before dictation starts.

**Relationships**

- Paired with `Transcription Provider Selection`.
- Used to derive `Rewrite Configuration`.
- Participates in `Provider Configuration Validation`.

---

### 3. Provider Pair

Represents the selected provider combination for the two-step BYOK pipeline.

**Fields**

- `transcriptionProvider`
- `rewriteProvider`

**Supported default combinations**

- `OpenAI -> OpenAI`
- `Groq -> Groq`
- `Groq -> OpenAI`

**Unsupported default combination**

- `OpenAI -> Groq`

**Responsibilities**

- Defines the provider-level shape of the BYOK pipeline.
- Determines whether one or two provider API keys are required.
- Determines which default model pair should be used.

**Validation rules**

- The pair must always have both values populated in BYOK mode.
- `OpenAI -> Groq` is a settings/UI policy warning in the current implementation rather than a direct-route validation failure.

**State implications**

- Same-provider pair: one provider key is sufficient if rewrite is enabled.
- Mixed-provider pair: both provider keys are required.

---

### 4. Transcription Configuration

Represents the resolved provider-specific configuration used to build the transcription service.

**Fields**

- `provider`
- `apiKey`
- `baseURL`
- `transcriptionModel`
- optional transport metadata already supported by the current configuration layer

**Responsibilities**

- Supplies the OpenAI-compatible SDK layer with the provider-specific values for transcription.
- Encodes the default transcription model for the selected provider.

**Validation rules**

- Must not be created unless the required provider key is present.
- Must use the provider-appropriate base URL.
- Must use a transcription-capable model for the selected provider.

**Relationships**

- Derived from `Transcription Provider Selection`.
- Consumed by the Mac transcription service implementation.

---

### 5. Rewrite Configuration

Represents the resolved provider-specific configuration used to build the rewrite service.

**Fields**

- `provider`
- `apiKey`
- `baseURL`
- `rewriteModel`
- optional transport metadata already supported by the current configuration layer

**Responsibilities**

- Supplies the OpenAI-compatible SDK layer with the provider-specific values for rewrite.
- Encodes the default rewrite model for the selected provider.

**Validation rules**

- Must not be created unless the required provider key is present.
- Must use the provider-appropriate base URL.
- Must use a rewrite-capable model for the selected provider.

**Relationships**

- Derived from `Rewrite Provider Selection`.
- Consumed by the Mac rewrite service implementation.

---

### 6. Provider Configuration Validation

Represents the preflight result that checks whether the selected BYOK provider pair is runnable before dictation begins.

**Purpose**

- Block dictation before any remote request when required provider keys are missing.

**Derived inputs**

- `Transcription Provider Selection`
- `Rewrite Provider Selection`
- rewrite enabled state
- provider-scoped key presence from local secure storage

**Possible outcomes**

- `valid`
- `missing transcription provider key`
- `missing rewrite provider key`
- `missing both required provider keys`

**Responsibilities**

- Produces step-aware configuration failures.
- Prevents the pipeline from starting when prerequisites are not met.

**Validation rules**

- Must run before any remote transcription or rewrite request in BYOK mode.
- Must identify the blocked step and the missing provider.
- Must remain separate from the settings-level unsupported-pair warning policy.

---

### 7. Intermediate Transcript

Represents the text returned from the transcription step and held inside the Mac app before rewrite.

**Fields**

- `text`
- `sourceProvider`

**Responsibilities**

- Serves as the internal handoff value between transcription and rewrite.
- Is not the final user-visible output of the feature.

**Validation rules**

- Must not be empty or whitespace-only.
- If invalid, the flow fails before rewrite begins.

**Relationships**

- Produced by `Transcription Configuration` + transcription service.
- Consumed by `Rewrite Configuration` + rewrite service.

---

### 8. Final Dictation Output

Represents the final rewritten text returned to the user after successful BYOK dictation cleanup.

**Fields**

- `text`
- `transcriptionProvider`
- `rewriteProvider`

**Responsibilities**

- Serves as the only user-visible successful output of the two-step BYOK flow.

**Validation rules**

- Must not be empty or whitespace-only.
- Must only be emitted after successful transcription and successful rewrite.

---

### 9. Provider-Aware Dictation Failure

Represents structured failure states for the BYOK dictation flow.

**Failure categories relevant to this feature**

- `configuration failure`
- `transcription failure`
- `rewrite failure`

**Minimum fields required by this feature**

- `stage`
  - `transcription`
  - `rewrite`
  - `preflight`
- `provider`
- user-facing message

**Responsibilities**

- Distinguishes missing configuration from runtime provider failure.
- Distinguishes transcription-stage failure from rewrite-stage failure.
- Supports user-directed configuration guidance.

**Validation rules**

- Preflight failures must identify the missing provider key by step.
- Runtime failures must preserve the provider responsible for the failure.

## State Transitions

### BYOK Dictation Flow

1. `settings loaded`
2. `provider pair resolved`
3. `provider configuration validation`
4. `transcription configuration resolved`
5. `rewrite configuration resolved`
6. `transcription request started`
7. `intermediate transcript produced`
8. `rewrite request started`
9. `final dictation output produced`

### Failure Transitions

- If validation fails:
  - stop before transcription
  - emit provider-aware configuration failure
- If transcription fails:
  - stop before rewrite
  - emit transcription-stage failure
- If transcription succeeds but transcript is empty:
  - treat as invalid transcription result
  - stop before rewrite
- If rewrite fails:
  - do not emit final output
  - emit rewrite-stage failure

## Defaulting Rules

- `transcriptionProvider` defaults to the current existing single-provider default behavior.
- `rewriteProvider` defaults to the same value as `transcriptionProvider`.
- Provider API keys remain stored by provider, not by step.
- Default models are resolved from the selected provider pair.
- `OpenAI -> Groq` does not receive a first-class default model combination in this feature.

## Relationships

- `Transcription Provider Selection` and `Rewrite Provider Selection` combine into a `Provider Pair`.
- The `Provider Pair` drives `Transcription Configuration`, `Rewrite Configuration`, and `Provider Configuration Validation`.
- `Provider Configuration Validation` must pass before the feature can produce an `Intermediate Transcript`.
- `Intermediate Transcript` is the required handoff input to the rewrite step and precedes `Final Dictation Output`.
- `Provider-Aware Dictation Failure` can be produced from preflight validation, transcription, or rewrite, but never alongside a successful final output.

## Persistence

- `transcriptionProvider` is persisted in Mac preferences.
- `rewriteProvider` is persisted in Mac preferences and defaults to the transcription provider until explicitly changed.
- Provider API keys are persisted per provider in secure local storage rather than per pipeline step.
- Provider pair validation results, intermediate transcripts, final outputs, and runtime failures are transient and are not persisted by this feature.

## Invariants

- A BYOK direct-mode provider pair always has both a transcription provider and a rewrite provider.
- No remote request should start until provider configuration validation succeeds for the selected pair.
- The intermediate transcript is never the final user-visible success result for this feature.
- A final dictation output only exists after both transcription and rewrite succeed.
- Provider credentials remain provider-scoped even when the two steps choose different providers.
