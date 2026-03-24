# Tasks: BYOK Remote Transcribe and Rewrite Provider Selection on Mac

**Input**: Design documents from `/specs/005-transcribe-details/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md

**Completed design artifacts**: `spec.md`, `research.md`, `plan.md`, and `data-model.md` are already prepared for this feature. The tasks below cover the remaining implementation and validation work only.

**Tests**: This feature explicitly requires automated coverage for provider selection, BYOK preflight validation, mixed-provider execution, and regression safety.

**Organization**: Tasks are grouped by user story so each story can be implemented and validated independently.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel when the tasks touch different files and do not depend on unfinished work
- **[Story]**: Maps the task to a specific user story from `spec.md`
- Every task includes an exact file path

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Align the remaining implementation work with the completed design docs and current code layout.

- [X] T001 Inspect `/Users/nd/Developer/Stet/apps/mac/Stet/Shared/Utilities/DictationSettingsStore.swift`, `/Users/nd/Developer/Stet/apps/mac/Stet/Core/DictationPipeline/DictationPipelineFactory.swift`, and `/Users/nd/Developer/Stet/apps/mac/Stet/Core/Speech/ConfigurableSpeechService.swift` to confirm the final write scope before code changes
- [X] T002 Inspect `/Users/nd/Developer/Stet/apps/mac/Stet/Core/OpenAI/OpenAIConfiguration.swift`, `/Users/nd/Developer/Stet/apps/mac/Stet/Core/OpenAI/OpenAISDKClientFactory.swift`, `/Users/nd/Developer/Stet/apps/mac/Stet/Core/Transcribed/OpenAITranscriptionService.swift`, and `/Users/nd/Developer/Stet/apps/mac/Stet/Core/Rewrite/OpenAIRewriteService.swift` to confirm which naming and adapter layers stay provider-neutral versus OpenAI-compatible

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Establish the shared configuration, naming, and validation model required by all user stories

**⚠️ CRITICAL**: No user story work should begin until this phase is complete

- [X] T003 Update `/Users/nd/Developer/Stet/apps/mac/Stet/Shared/Utilities/MacPreferences.swift` to introduce separate persisted keys for transcription provider and rewrite provider
- [X] T004 Update `/Users/nd/Developer/Stet/apps/mac/Stet/Shared/Utilities/DictationSettingsStore.swift` to load and save `transcriptionProvider` and `rewriteProvider`, while keeping API keys stored by provider in Keychain
- [X] T005 Update the snapshot model in `/Users/nd/Developer/Stet/apps/mac/Stet/Shared/Utilities/DictationSettingsStore.swift` to carry separate provider selections and separate per-step provider configurations for BYOK
- [X] T006 Apply the provider-neutral naming cleanup for configuration-facing types and directories in `/Users/nd/Developer/Stet/apps/mac/Stet/Core/OpenAI/`, `/Users/nd/Developer/Stet/apps/mac/Stet/Core/DictationPipeline/`, and `/Users/nd/Developer/Stet/apps/mac/Stet/Shared/Utilities/` without introducing a generalized provider framework
- [X] T007 Implement provider-pair defaulting and supported default model resolution in `/Users/nd/Developer/Stet/apps/mac/Stet/Core/OpenAI/OpenAIConfiguration.swift` or its provider-neutral replacement
- [X] T008 Implement step-aware BYOK preflight validation in `/Users/nd/Developer/Stet/apps/mac/Stet/Core/DictationPipeline/DictationExecutionRoute.swift` so provider requirements are resolved before runtime work begins
- [X] T009 Update `/Users/nd/Developer/Stet/apps/mac/Stet/Features/Dictation/DictationFailure.swift` and related provider error types to represent step-aware configuration failures for transcription and rewrite

**Checkpoint**: Shared provider modeling and BYOK preflight are ready; user story work can now proceed safely

---

## Phase 3: User Story 1 - Choose the Transcription Provider (Priority: P1) 🎯 MVP

**Goal**: Let BYOK users independently choose `OpenAI` or `Groq` for the transcription step.

**Independent Test**: Change the transcription provider setting on Mac, start BYOK dictation, and verify transcription uses the selected provider and requires the matching provider key.

### Tests for User Story 1

- [X] T010 [P] [US1] Add settings persistence coverage for transcription provider selection in `/Users/nd/Developer/Stet/apps/mac/StetTests/Features/MacShell/Openai/MacOpenAISettingsViewModelTests.swift`
- [X] T011 [P] [US1] Add snapshot and route coverage for transcription provider selection in `/Users/nd/Developer/Stet/apps/mac/StetTests/Core/DictationPipeline/DictationPipelineTests.swift`

### Implementation for User Story 1

- [X] T012 [US1] Update `/Users/nd/Developer/Stet/apps/mac/Stet/Core/DictationPipeline/DictationPipelineFactory.swift` so the BYOK transcription service is built from the selected transcription provider configuration
- [X] T013 [US1] Update `/Users/nd/Developer/Stet/apps/mac/Stet/Core/Speech/ConfigurableSpeechService.swift` to preserve the current two-step flow while consuming the new transcription-specific pipeline inputs
- [X] T014 [US1] Update `/Users/nd/Developer/Stet/apps/mac/Stet/Features/MacShell/Openai/MacOpenAISettingsViewModel.swift` to expose a dedicated transcription provider selection in BYOK mode
- [X] T015 [US1] Update the related macOS settings UI under `/Users/nd/Developer/Stet/apps/mac/Stet/Features/MacShell/Openai/` to present the transcription provider selection clearly

**Checkpoint**: Users can choose the transcription provider independently, and the BYOK pipeline uses that provider for transcription

---

## Phase 4: User Story 2 - Choose the Rewrite Provider Independently (Priority: P1)

**Goal**: Let BYOK users choose `OpenAI` or `Groq` for rewrite independently from the transcription provider.

**Independent Test**: Set different transcription and rewrite providers, then verify the Mac app validates both provider requirements and builds the rewrite step from the selected rewrite provider.

### Tests for User Story 2

- [X] T016 [P] [US2] Add settings persistence coverage for rewrite provider selection and provider-pair defaulting in `/Users/nd/Developer/Stet/apps/mac/StetTests/Features/MacShell/Openai/MacOpenAISettingsViewModelTests.swift`
- [X] T017 [P] [US2] Add mixed-provider pipeline coverage for `Groq -> OpenAI` and supported provider-pair defaults in `/Users/nd/Developer/Stet/apps/mac/StetTests/Core/DictationPipeline/DictationPipelineTests.swift`

### Implementation for User Story 2

- [X] T018 [US2] Update `/Users/nd/Developer/Stet/apps/mac/Stet/Core/DictationPipeline/DictationPipelineFactory.swift` so the BYOK rewrite service is built from the selected rewrite provider configuration instead of sharing the transcription provider config
- [X] T019 [US2] Implement the supported and unsupported default provider/model combinations in `/Users/nd/Developer/Stet/apps/mac/Stet/Core/OpenAI/OpenAIConfiguration.swift` or its provider-neutral replacement, including no first-class default for `OpenAI -> Groq`
- [X] T020 [US2] Update `/Users/nd/Developer/Stet/apps/mac/Stet/Features/MacShell/Openai/MacOpenAISettingsViewModel.swift` to expose a dedicated rewrite provider selection in BYOK mode
- [X] T021 [US2] Update the related macOS settings UI under `/Users/nd/Developer/Stet/apps/mac/Stet/Features/MacShell/Openai/` to present the rewrite provider selection independently from transcription

**Checkpoint**: Users can choose transcription and rewrite providers independently, and supported provider pairs resolve to the expected default models

---

## Phase 5: User Story 3 - Run Dictation as Two Remote Steps (Priority: P1)

**Goal**: Keep BYOK dictation as an explicit two-step remote flow where transcription feeds rewrite and only the rewritten text is returned to the user.

**Independent Test**: Run BYOK dictation for supported provider pairs and verify the pipeline transcribes first, rewrites second, returns rewritten text on success, and skips rewrite when transcription fails.

### Tests for User Story 3

- [X] T022 [P] [US3] Add BYOK runtime coverage for supported provider pairs in `/Users/nd/Developer/Stet/apps/mac/StetTests/Core/Speech/ConfigurableSpeechServiceTests.swift`
- [X] T023 [P] [US3] Add coverage that transcription failure prevents rewrite and rewrite failure returns a failed dictation result in `/Users/nd/Developer/Stet/apps/mac/StetTests/Core/Speech/ConfigurableSpeechServiceTests.swift`

### Implementation for User Story 3

- [X] T024 [US3] Update `/Users/nd/Developer/Stet/apps/mac/Stet/Core/Rewrite/TextRewriteService.swift` and related rewrite request construction to preserve the current dictation cleanup behavior with per-step provider configuration
- [X] T025 [US3] Update `/Users/nd/Developer/Stet/apps/mac/Stet/Core/Speech/ConfigurableSpeechService.swift` so the intermediate transcript remains internal and the final user-visible output is always the rewrite result

**Checkpoint**: BYOK dictation behaves as a clear two-step remote flow for the supported provider pairs

---

## Phase 6: User Story 4 - Get Clear Configuration Errors Before Dictation Starts (Priority: P2)

**Goal**: Fail fast with step-aware, user-directed configuration errors before dictation starts when required provider keys are missing.

**Independent Test**: Try missing-key combinations and verify the Mac app blocks execution before remote work starts and reports which step and provider are misconfigured.

### Tests for User Story 4

- [X] T026 [P] [US4] Add BYOK preflight coverage for missing transcription keys, missing rewrite keys, and missing both keys in `/Users/nd/Developer/Stet/apps/mac/StetTests/Core/DictationPipeline/DictationPipelineTests.swift`
- [X] T027 [P] [US4] Add Dictation UI error-mapping coverage for step-aware provider configuration failures in `/Users/nd/Developer/Stet/apps/mac/StetTests/Features/Dictation/DictationViewModelTests.swift`

### Implementation for User Story 4

- [X] T028 [US4] Update `/Users/nd/Developer/Stet/apps/mac/Stet/Core/Speech/ConfigurableSpeechService.swift` to run BYOK provider preflight before any remote dictation request starts
- [X] T029 [US4] Update `/Users/nd/Developer/Stet/apps/mac/Stet/Features/Dictation/DictationFailure.swift` and related provider error sources to produce step-aware, user-directed configuration messages
- [X] T030 [US4] Update the dictation-facing UI under `/Users/nd/Developer/Stet/apps/mac/Stet/Features/Dictation/` and `/Users/nd/Developer/Stet/apps/mac/Stet/Features/MacShell/DictationPanel/` so the new configuration failures are surfaced cleanly without regressing current error handling

**Checkpoint**: Missing provider keys are blocked before execution and surfaced with clear, step-aware guidance

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Finish regression validation, documentation alignment, and cleanup that affects multiple user stories

- [X] T031 Run the affected macOS test suites covering `/Users/nd/Developer/Stet/apps/mac/StetTests/Core/DictationPipeline/`, `/Users/nd/Developer/Stet/apps/mac/StetTests/Core/Speech/`, and `/Users/nd/Developer/Stet/apps/mac/StetTests/Features/Dictation/`
- [X] T032 Verify relay/managed regression behavior remains unchanged in `/Users/nd/Developer/Stet/apps/mac/StetTests/Core/DictationPipeline/DictationPipelineTests.swift` and `/Users/nd/Developer/Stet/apps/mac/StetTests/Core/Speech/ConfigurableSpeechServiceTests.swift`
- [X] T033 [P] Refresh `/Users/nd/Developer/Stet/specs/005-transcribe-details/quickstart.md` with the final implementation entry points, validation matrix, and supported provider combinations
- [X] T034 Run quickstart validation and record the exact commands and observed outcomes in `/Users/nd/Developer/Stet/specs/005-transcribe-details/quickstart.md`

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies
- **Foundational (Phase 2)**: Depends on Setup completion and blocks all user stories
- **User Story 1-4 (Phase 3-6)**: Depend on Foundational completion
- **Polish (Phase 7)**: Depends on all targeted user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Starts after Foundational; independent MVP entry point for provider-specific transcription
- **User Story 2 (P1)**: Starts after Foundational; depends conceptually on the dual-provider settings model but remains independently testable
- **User Story 3 (P1)**: Starts after User Stories 1 and 2 establish per-step provider wiring
- **User Story 4 (P2)**: Starts after Foundational; benefits from the new settings and error model, but is independently testable as a preflight/error behavior slice

### Within Each User Story

- Tests should be updated before or alongside implementation so the new behavior is pinned down early
- Bottom-layer configuration and snapshot changes must land before settings/UI integration
- Preflight and provider-pair defaulting must land before runtime flow validation
- Pipeline assembly changes must land before runtime flow validation
- Error model changes must land before final UI messaging polish

### Parallel Opportunities

- `T010` and `T011` can run in parallel
- `T016` and `T017` can run in parallel
- `T022` and `T023` can run in parallel
- `T026` and `T027` can run in parallel
- Documentation refresh `T033` can run in parallel with late implementation once file ownership is clear

## Parallel Example: User Story 2

```bash
# Launch rewrite-provider persistence and pipeline coverage work together:
Task: "T016 [P] [US2] Add settings persistence coverage for rewrite provider selection and provider-pair defaulting in /Users/nd/Developer/Stet/apps/mac/StetTests/Features/MacShell/Openai/MacOpenAISettingsViewModelTests.swift"
Task: "T017 [P] [US2] Add mixed-provider pipeline coverage for Groq -> OpenAI and supported provider-pair defaults in /Users/nd/Developer/Stet/apps/mac/StetTests/Core/DictationPipeline/DictationPipelineTests.swift"
```

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational
3. Complete Phase 3: User Story 1
4. Validate that BYOK transcription provider selection works independently

### Incremental Delivery

1. Ship the dual-provider foundation
2. Add independent transcription provider selection
3. Add independent rewrite provider selection and provider-pair defaults
4. Lock the two-step BYOK runtime behavior
5. Add step-aware preflight and user-facing configuration errors
6. Finish regression validation and documentation

### Suggested MVP Scope

The smallest useful increment is:

- Foundational phase
- User Story 1

That gives the codebase a real split between single-provider and capability-specific provider modeling while keeping runtime risk controlled.

## Notes

- `contracts/` is intentionally deferred for this feature and does not block implementation
- This task list covers remaining implementation work only; already-completed design docs are not repeated as checklist items
- Relay/managed behavior is a regression-sensitive area and must remain unchanged unless explicitly revisited in a future spec
