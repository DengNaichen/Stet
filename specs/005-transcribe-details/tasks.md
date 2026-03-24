# Tasks: BYOK Capability-Split Provider Refactor on Mac

**Input**: Design documents from `/specs/005-transcribe-details/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md

**Completed design artifacts**: `spec.md`, `research.md`, `plan.md`, and `data-model.md` are already prepared for this feature. The tasks below cover the capability-split refactor, policy relocation, naming/file cleanup, and validation work.

**Tests**: This feature explicitly requires automated coverage for capability-specific config assembly, provider selection, BYOK preflight validation, mixed-provider execution, settings/UI policy, and regression safety.

**Organization**: Tasks are grouped by architectural slice so the provider boundary can be cleaned up without leaving half-migrated naming or runtime wiring behind.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel when the tasks touch different files and do not depend on unfinished work
- **[Story]**: Maps the task to a specific user story from `spec.md`
- Every task includes an exact file path

## Phase 1: Boundary Setup

**Purpose**: Confirm the final write scope for the capability split and document the new folder/type boundary.

- [X] T001 Inspect `/Users/nd/Developer/Stet/apps/mac/Stet/Shared/Utilities/DictationSettingsStore.swift`, `/Users/nd/Developer/Stet/apps/mac/Stet/Core/DictationPipeline/DictationPipelineFactory.swift`, and `/Users/nd/Developer/Stet/apps/mac/Stet/Core/Speech/ConfigurableSpeechService.swift` to confirm the final write scope before code changes
- [X] T002 Inspect `/Users/nd/Developer/Stet/apps/mac/Stet/Core/AIProviders/OpenAICompatible/OpenAISDKClientFactory.swift`, `/Users/nd/Developer/Stet/apps/mac/Stet/Core/AIProviders/OpenAI/OpenAITranscriptionService.swift`, and `/Users/nd/Developer/Stet/apps/mac/Stet/Core/AIProviders/OpenAI/OpenAIRewriteService.swift` to confirm which naming and adapter layers stay OpenAI-compatible

---

## Phase 2: Foundational Types and Policy

**Purpose**: Establish the capability-specific configuration model, adapter boundary, and settings/UI policy required by all later work

**⚠️ CRITICAL**: No user story work should begin until this phase is complete

- [X] T003 Introduce provider-neutral capability config types and shared endpoint/auth config under `/Users/nd/Developer/Stet/apps/mac/Stet/Core/AIProviders/`
- [X] T004 Move provider defaults and settings/UI pair-policy resolution into the new provider-neutral layer without introducing a generalized provider framework
- [X] T005 Update `/Users/nd/Developer/Stet/apps/mac/Stet/Shared/Utilities/DictationSettingsStore.swift` so the snapshot carries separate provider selections and separate capability configs for BYOK
- [X] T006 Apply naming cleanup for configuration-facing types and files while keeping `OpenAI*` names only for the OpenAI-compatible adapter layer
- [X] T007 Remove execution-time unsupported-pair enforcement from `/Users/nd/Developer/Stet/apps/mac/Stet/Core/DictationPipeline/DictationExecutionRoute.swift` while keeping step-aware BYOK preflight validation
- [X] T008 Update `/Users/nd/Developer/Stet/apps/mac/Stet/Features/Dictation/DictationFailure.swift` and related provider error types to preserve step-aware configuration failures and keep unsupported-pair messaging decoupled from execution

**Checkpoint**: Shared provider modeling, adapter boundaries, and BYOK preflight are ready; feature-level wiring can now proceed safely

---

## Phase 3: Capability Wiring and Adapter Migration

**Goal**: Rewire the runtime to consume separate transcription and rewrite configs while preserving the two-step BYOK flow and keeping provider-specific transport in thin adapters.

**Independent Test**: Run BYOK dictation for same-provider and mixed-provider setups and verify transcription and rewrite are built from the correct capability-specific configs.

### Tests for Phase 3

- [X] T009 [P] Add snapshot and route coverage for separate transcription and rewrite configs in `/Users/nd/Developer/Stet/apps/mac/StetTests/Core/DictationPipeline/DictationPipelineTests.swift`
- [X] T010 [P] Add adapter coverage for capability-specific config input in `/Users/nd/Developer/Stet/apps/mac/StetTests/Core/AIProviders/OpenAICompatible/OpenAITests.swift`
- [X] T011 [P] Add BYOK runtime coverage for same-provider and mixed-provider capability wiring in `/Users/nd/Developer/Stet/apps/mac/StetTests/Core/Speech/ConfigurableSpeechServiceTests.swift`

### Implementation for Phase 3

- [X] T012 Update `/Users/nd/Developer/Stet/apps/mac/Stet/Core/DictationPipeline/DictationPipelineFactory.swift` so direct transcription and rewrite services are built from separate capability-specific configs
- [X] T013 Update `/Users/nd/Developer/Stet/apps/mac/Stet/Core/AIProviders/OpenAI/OpenAITranscriptionService.swift` and `/Users/nd/Developer/Stet/apps/mac/Stet/Core/AIProviders/OpenAI/OpenAIRewriteService.swift` to consume the new capability-specific configs
- [X] T014 Update `/Users/nd/Developer/Stet/apps/mac/Stet/Core/AIProviders/OpenAICompatible/OpenAISDKClientFactory.swift` and onboarding API-key validation to use the shared OpenAI-compatible endpoint/auth config
- [X] T015 Keep `/Users/nd/Developer/Stet/apps/mac/Stet/Core/Speech/ConfigurableSpeechService.swift` on the current two-step flow while consuming the new pipeline inputs

**Checkpoint**: The runtime uses a provider-neutral capability boundary with OpenAI-compatible adapters above it

---

## Phase 4: Settings/UI Policy and Messaging

**Goal**: Keep provider selection flexible in lower layers while enforcing product-specific unsupported-pair policy only in settings/UI.

**Independent Test**: Verify settings still show the current unsupported-pair warning for `OpenAI -> Groq`, while route resolution no longer rejects that combination.

### Tests for Phase 4

- [X] T016 [P] Add settings persistence and warning coverage in `/Users/nd/Developer/Stet/apps/mac/StetTests/Features/MacShell/Openai/MacOpenAISettingsViewModelTests.swift`
- [X] T017 [P] Add Dictation UI error-mapping coverage for step-aware provider configuration failures and preserved unsupported-pair messaging in `/Users/nd/Developer/Stet/apps/mac/StetTests/Features/Dictation/DictationViewModelTests.swift`

### Implementation for Phase 4

- [X] T018 Update `/Users/nd/Developer/Stet/apps/mac/Stet/Features/MacShell/Openai/MacOpenAISettingsViewModel.swift` so unsupported-pair policy comes from settings/UI policy only
- [X] T019 Update dictation-facing failure messaging under `/Users/nd/Developer/Stet/apps/mac/Stet/Features/Dictation/` so step-aware configuration failures remain clear without depending on execution-time pair rejection

**Checkpoint**: Unsupported-pair policy is now a settings/UI concern, not a runtime assembly concern

---

## Phase 5: Polish, Naming, and Cross-Cutting Concerns

**Purpose**: Finish regression validation, documentation alignment, and cleanup that affects multiple user stories

- [X] T020 Apply any remaining file/folder renames and configuration-facing naming cleanup needed to make the capability boundary obvious in the source tree
- [X] T021 Run the affected macOS test suites covering `/Users/nd/Developer/Stet/apps/mac/StetTests/Core/DictationPipeline/`, `/Users/nd/Developer/Stet/apps/mac/StetTests/Core/AIProviders/OpenAICompatible/`, `/Users/nd/Developer/Stet/apps/mac/StetTests/Core/Speech/`, and `/Users/nd/Developer/Stet/apps/mac/StetTests/Features/Dictation/`
- [X] T022 Verify relay/managed regression behavior remains unchanged in `/Users/nd/Developer/Stet/apps/mac/StetTests/Core/DictationPipeline/DictationPipelineTests.swift` and `/Users/nd/Developer/Stet/apps/mac/StetTests/Core/Speech/ConfigurableSpeechServiceTests.swift`
- [X] T023 [P] Refresh `/Users/nd/Developer/Stet/specs/005-transcribe-details/plan.md` and `/Users/nd/Developer/Stet/specs/005-transcribe-details/tasks.md` so they match the final capability-split architecture
- [ ] T024 [P] Refresh `/Users/nd/Developer/Stet/specs/005-transcribe-details/quickstart.md` with the final implementation entry points, validation matrix, and supported provider combinations

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies
- **Foundational (Phase 2)**: Depends on Setup completion and blocks all later work
- **Capability Wiring (Phase 3)**: Depends on Foundational completion
- **Settings/UI Policy (Phase 4)**: Depends on Foundational completion and benefits from Capability Wiring
- **Polish (Phase 5)**: Depends on all targeted implementation phases being complete

### User Story Dependencies

- **Phase 3**: Starts after Foundational and establishes the new runtime boundary
- **Phase 4**: Starts after Foundational and depends on the new policy type and settings model
- **Phase 5**: Starts after the runtime and policy layers are stable

### Within Each User Story

- Tests should be updated before or alongside implementation so the new behavior is pinned down early
- Bottom-layer configuration and snapshot changes must land before settings/UI integration
- Preflight and provider-pair defaulting must land before runtime flow validation
- Pipeline assembly changes must land before runtime flow validation
- Error model changes must land before final UI messaging polish

### Parallel Opportunities

- `T009`, `T010`, and `T011` can run in parallel
- `T016` and `T017` can run in parallel
- Documentation refresh `T023` can run in parallel with late implementation once file ownership is clear

## Parallel Example: Phase 3

```bash
# Launch capability-config and adapter coverage work together:
Task: "T009 [P] Add snapshot and route coverage for separate transcription and rewrite configs in /Users/nd/Developer/Stet/apps/mac/StetTests/Core/DictationPipeline/DictationPipelineTests.swift"
Task: "T010 [P] Add adapter coverage for capability-specific config input in /Users/nd/Developer/Stet/apps/mac/StetTests/Core/AIProviders/OpenAICompatible/OpenAITests.swift"
```

## Implementation Strategy

### MVP First

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational
3. Complete Phase 3: Capability Wiring and Adapter Migration
4. Validate that BYOK transcription and rewrite are wired through separate configs

### Incremental Delivery

1. Ship the capability-specific config foundation
2. Migrate the runtime and adapters to the new boundary
3. Relocate unsupported-pair policy to settings/UI
4. Finish regression validation and documentation

### Suggested MVP Scope

The smallest useful increment is the combination of Foundational + Capability Wiring. That gives the codebase a real split between cross-capability vendor config and capability-specific provider-neutral modeling while keeping runtime risk controlled.

## Notes

- `contracts/` is intentionally deferred for this feature and does not block implementation
- This task list covers remaining implementation work only; already-completed design docs are not repeated as checklist items
- Relay/managed behavior is a regression-sensitive area and must remain unchanged unless explicitly revisited in a future spec
