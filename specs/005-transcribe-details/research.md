# Research: BYOK Remote Transcribe and Rewrite Provider Selection on Mac

## Decision 1: Keep the BYOK dictation flow as a two-step remote pipeline

Decision: In BYOK mode, the Mac app will run dictation as two separate remote steps:

1. Send recorded audio to a remote ASR provider.
2. Send the resulting transcript to a remote rewrite provider for dictation cleanup.

Rationale: Existing experiments already validate that the two-stage pipeline is the right product shape for quality. The ASR step and the cleanup step have different quality and cost tradeoffs, so the feature should model them as separate steps instead of forcing a single provider decision.

Alternatives considered:

- Single-step remote flow where the final text comes back from one provider: rejected because it removes the ability to optimize ASR and cleanup independently.
- Managed/relay-specific behavior in this feature: rejected because this spec is intentionally scoped to Mac-side BYOK behavior only.

## Decision 2: Support independent provider selection for transcription and rewrite

Decision: The Mac app will support separate BYOK selections for:

- `transcriptionProvider`
- `rewriteProvider`

Each selection may be `OpenAI` or `Groq`.

Rationale: The current implementation only carries one provider choice, which incorrectly couples transcription and rewrite. This is the main product gap for the feature. Independent selection is justified because the best provider for ASR is not always the best provider for rewrite.

Alternatives considered:

- Keep a single shared provider for both steps: rejected because it does not solve the missing capability.
- Let provider selection vary only by hidden defaults: rejected because the user explicitly needs control over each step.

## Decision 3: Reuse the existing OpenAI-compatible SDK integration

Decision: Keep using the current third-party `OpenAI` Swift SDK integration layer for both OpenAI and Groq-compatible requests.

Rationale: The Mac client already routes both providers through a shared OpenAI-compatible configuration shape:

- OpenAI uses `https://api.openai.com/v1`
- Groq uses `https://api.groq.com/openai/v1`

The current codebase now centralizes provider endpoint/auth handling in a shared OpenAI-compatible configuration layer and reuses the same SDK-backed request stack for OpenAI-compatible providers. Splitting provider selection by step does not require a second networking stack.

Relevant implementation points:

- `apps/mac/Stet/Core/AIProviders/OpenAICompatible/OpenAICompatibleProviderConfiguration.swift`
- `apps/mac/Stet/Core/AIProviders/OpenAICompatible/OpenAISDKClientFactory.swift`
- `apps/mac/Stet/Core/AIProviders/OpenAI/OpenAITranscriptionService.swift`
- `apps/mac/Stet/Core/AIProviders/OpenAI/OpenAIRewriteService.swift`

Alternatives considered:

- Introduce a separate Groq-specific client implementation: rejected because the current OpenAI-compatible path already supports the needed requests.
- Hide provider differences behind backend orchestration: rejected because this feature is specifically about Mac-side BYOK behavior.

## Decision 4: Validate required API keys before dictation starts

Decision: The Mac app will preflight provider configuration before starting BYOK dictation.

Validation rules:

- If transcription uses OpenAI, an OpenAI key is required.
- If transcription uses Groq, a Groq key is required.
- If rewrite uses OpenAI, an OpenAI key is required.
- If rewrite uses Groq, a Groq key is required.
- If transcription and rewrite use different providers, both keys are required.

Rationale: Mixed-provider setups can require two different API keys. Failing before remote work begins gives clearer UX than allowing recording and then failing mid-pipeline.

Alternatives considered:

- Fail lazily when the missing step is reached: rejected because it delays feedback and wastes a recording.
- Keep provider-level errors without step-level context: rejected because users need to know whether transcription or rewrite is blocked.

## Decision 5: Use explicit default provider/model combinations

Decision: The feature will define supported default combinations for BYOK dictation cleanup.

Supported default combinations:

1. `Groq -> Groq`
   - Transcription model: `whisper-large-v3-turbo`
   - Rewrite model: `llama-3.3-70b-versatile`

2. `OpenAI -> OpenAI`
   - Transcription model: `gpt-4o-mini-transcribe`
   - Rewrite model: `gpt-5.4-nano-2026-03-17`

3. `Groq -> OpenAI`
   - Transcription model: `whisper-large-v3-turbo`
   - Rewrite model: `gpt-5.4-nano-2026-03-17`

Unsupported default combination:

4. `OpenAI -> Groq`
   - No default combination will be provided.

Rationale: Prior experiments show that rewrite quality and overall product quality are not symmetric across all provider pairings. The chosen defaults reflect combinations that are worth supporting as first-class presets. The `OpenAI ASR -> Groq rewrite` path was tested and judged too weak in final quality to justify a default setup.

Alternatives considered:

- Provide defaults for all four permutations: rejected because one of the combinations does not meet quality expectations.
- Force a single global default regardless of provider selection: rejected because the default model pair should follow the chosen provider path.

## Decision 6: Keep the research compact and implementation-facing

Decision: This feature research intentionally summarizes prior experiments instead of reproducing the full raw notes from the repo root.

Rationale: The root `research.md` is useful source material, but it is broader and more verbose than this feature needs. The feature-level research should capture only the conclusions that directly constrain Mac-side product and implementation decisions.

Source material incorporated:

- Root-level model comparison and cost/latency findings from `/Users/nd/Developer/Stet/research.md`
- Current provider defaults in `apps/mac/Stet/Core/AIProviders/OpenAICompatible/OpenAICompatibleProviderConfiguration.swift`

Alternatives considered:

- Copy the full experimental write-up into this feature: rejected because it is too long and mixes product decisions with raw investigation detail.
- Omit prior research entirely: rejected because the provider and model defaults should be traceable to prior evaluation.
