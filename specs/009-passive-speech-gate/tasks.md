# Tasks: Unified Speech Capture and Contextual Passive Listening

**Input**: Design documents from `/specs/009-passive-speech-gate/`
**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`, `contracts/`, `quickstart.md`

**Tests**: Required by the specification's independent-test scenarios and measurable success criteria. Write each story's tests first and confirm they fail for the missing behavior before implementing it.

**Organization**: Tasks are grouped by user story. Repository-relative paths are from `/Users/nd/Developer/stet-project/Stet`.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel because it touches different files and has no dependency on another incomplete task in the same phase.
- **[Story]**: Maps the task to User Story 1, 2, or 3 from `spec.md`.

---

## Phase 1: Setup (Shared Test Infrastructure)

**Purpose**: Add only the missing test seams needed by the design; no new runtime dependency or model payload is introduced.

- [X] T001 [P] Add a `StetASRTests` SwiftPM test target and a module-import smoke test in `Public/Stet/Packages/StetEngine/Package.swift` and `Public/Stet/Packages/StetEngine/Tests/StetASRTests/StetASRSmokeTests.swift`
- [X] T002 [P] Add deterministic fake clock, normalized sample-frame, verifier, diarizer, Nano, and history spies in `Public/Stet/StetMacTests/Support/PassiveSpeechTestSupport.swift`

**Checkpoint**: Shared package and Mac test targets discover the new test support without adding downloaded models to Git.

---

## Phase 2: Foundational (Blocking Capture and History Contracts)

**Purpose**: Establish the public history contract and the one normalized microphone stream used by passive and active modes.

**⚠️ CRITICAL**: Complete this phase before implementing any user story.

- [X] T003 [P] Add failing contract and migration tests for active defaults, passive fields, ordered regions, overlap validation, idempotent creation, unknown-entry errors, and export exclusion of biometric data in `Public/Stet/Packages/StetEngine/Tests/StetCoreTests/DictationHistoryServiceTests.swift`
- [X] T004 [P] Add failing tests for continuous normalized frame delivery, monotonic sample ranges, bounded pre-activation buffering, and exact boundary splitting in `Public/Stet/StetMacTests/Core/Audio/Capture/MacCaptureAudioFileRecorderTests.swift` and `Public/Stet/StetMacTests/Core/Audio/Recording/MacRecordingFileSupportTests.swift`
- [X] T005 Implement `CaptureMode`, processing state, delivery `notDelivered`, Codable speaker identities/regions, migration defaults, and export fields in `Public/Stet/Packages/StetEngine/Sources/StetCore/HistoryEntry.swift`
- [X] T006 Implement validated idempotent create/update/finish/fail passive-capture methods from the history contract in `Public/Stet/Packages/StetEngine/Sources/StetCore/DictationHistoryService.swift`
- [X] T007 Implement the normalized, epoch-tagged capture-frame value and its existing stream bridge seam in `Public/Stet/StetMac/Core/Speech/AudioCaptureEvent.swift` and `Public/Stet/StetMac/Core/Speech/AudioCaptureEventBridge.swift`
- [X] T008 Refactor the existing single AVCapture owner to remain available independently of an active file window and emit every converted 16 kHz mono frame once in `Public/Stet/StetMac/Core/Audio/Capture/MacCaptureAudioFileRecorder.swift` and `Public/Stet/StetMac/Core/Speech/MacAudioCaptureService.swift`
- [X] T009 Implement bounded frame retention and exact sample-boundary splitting without duplicate or missing ranges in `Public/Stet/StetMac/Core/Audio/Recording/MacRecordingFileSupport.swift`
- [X] T010 Run the new StetCore and Mac capture tests through `Public/Stet/Packages/StetEngine/Package.swift` and `Public/Stet/Makefile`

**Checkpoint**: History accepts validated passive records, and one Mac capture session can feed passive frames while still supporting active file capture.

---

## Phase 3: User Story 1 - All-day passive transcription on Mac (Priority: P1) 🎯 MVP

**Goal**: Keep low-cost passive listening available, discard other-only speech, admit conversations containing the owner, and persist faithful ordered turns labeled as self, known, other, or unresolved.

**Independent Test**: With no hotkey held, verify silence causes no verifier/ASR calls; other-only speech expires; other-then-owner replays retained opening audio; owner-initiated and continuing other turns are retained; timeouts close the entry; overlap and ambiguous identity stay unresolved.

### Tests for User Story 1

- [X] T011 [P] [US1] Add failing model-independent tests for L2 centroid creation, cosine matching, threshold/margin rejection, insufficient voice, and model revision/dimension mismatch in `Public/Stet/Packages/StetEngine/Tests/StetASRTests/SpeakerEmbeddingRecognizerTests.swift`
- [X] T012 [P] [US1] Add failing tests for one owner plus three known profiles, non-synchronizing Keychain storage, single/all deletion, no raw enrollment persistence, and re-enrollment status in `Public/Stet/StetMacTests/Core/Speech/SpeakerProfileStoreTests.swift`
- [X] T013 [P] [US1] Add failing adapter tests for streaming VAD start/end behavior, Sortformer finalized regions, separate activity/identity scores, and overlap unions in `Public/Stet/StetMacTests/Core/FluidAudio/FluidAudioPassiveSpeechAnalyzerTests.swift`
- [X] T014 [P] [US1] Add failing coordinator tests for 60-minute silence, 15-second bounded pending expiry, 0.4-second pre-roll, other-to-owner replay, owner-first admission, 10-second inactivity, 60-second owner absence, 30-second hard caps, stale epochs, and recovery after each inference failure in `Public/Stet/StetMacTests/Core/Speech/MacPassiveListeningCoordinatorTests.swift`
- [X] T015 [P] [US1] Extend failing history tests for incremental passive turn updates, exact unrewritten text, retained partial results on failure, and cleanup-safe completion in `Public/Stet/Packages/StetEngine/Tests/StetCoreTests/DictationHistoryServiceTests.swift`
- [X] T016 [P] [US1] Add failing settings tests for owner/known enrollment, deletion, consent copy, and profile-cap enforcement in `Public/Stet/StetMacTests/Features/MacShell/AudioSetting/MacAudioSettingsViewModelTests.swift`

### Implementation for User Story 1

- [X] T017 [P] [US1] Implement the thin CAMPPlus model loader, speech-window embedding extractor, normalized centroid, cosine score, threshold, and runner-up margin while retaining the existing Sherpa runtime in `Public/Stet/Packages/StetEngine/Sources/StetASR/SpeakerEmbeddingRecognizer.swift`
- [X] T018 [P] [US1] Implement local-only Codable Keychain profile storage with one owner, three known profiles, model metadata validation, and deletion in `Public/Stet/StetMac/Core/Speech/SpeakerProfileStore.swift`
- [X] T019 [P] [US1] Implement the FluidAudio streaming Silero VAD and accepted-audio Sortformer adapter, keeping activity confidence separate from identity similarity in `Public/Stet/StetMac/Core/FluidAudio/FluidAudioPassiveSpeechAnalyzer.swift`
- [X] T020 [US1] Add explicit enrollment capture, centroid creation, consent-facing copy, named-profile management, and immediate raw-audio disposal using the existing microphone test path in `Public/Stet/StetMac/Features/MacShell/AudioSetting/MacAudioSettingsViewModel.swift` and `Public/Stet/StetMac/Features/MacShell/AudioSetting/MacAudioSettingsView.swift`
- [X] T021 [US1] Implement the five-state actor, injected calibration values, 15-second RAM ring, rolling owner gate, deadlines, conversation IDs, and stale-epoch rejection in `Public/Stet/StetMac/Core/Speech/MacPassiveListeningCoordinator.swift`
- [X] T022 [US1] Replay admitted pending audio through Sortformer, merge adjacent same-identity regions, union overlap once as unresolved, add non-crossing 0.2-second padding, enforce the 30-second work cap, and serialize per-turn Nano calls in `Public/Stet/StetMac/Core/Speech/MacPassiveListeningCoordinator.swift`
- [X] T023 [US1] Create, incrementally update, finish, and fail one passive history entry per relevant conversation without rewrite, delivery, target-app metadata, or duplicate ranges in `Public/Stet/StetMac/Core/Speech/MacPassiveListeningCoordinator.swift`
- [X] T024 [US1] Start passive capture after permission/model readiness, stop and clear it on device or permission loss, and keep it alive through ordinary app lifecycle changes in `Public/Stet/StetMac/App/Lifecycle/MacAppModel.swift`
- [X] T025 [US1] Surface passive microphone use and relevant-conversation state through the existing app model and menu surface in `Public/Stet/StetMac/App/Lifecycle/MacAppModel.swift` and `Public/Stet/StetMac/Features/MacShell/MacMenuBarView.swift`
- [X] T026 [US1] Delete accepted turn WAVs on success, failure, cancellation, timeout, and shutdown, and remove only exact-prefix crash orphans at launch in `Public/Stet/StetMac/Core/Speech/MacPassiveListeningCoordinator.swift`
- [ ] T027 [US1] Run the consented owner/known/unknown corpus through `Public/Stet/scripts/speaker_verification_probe.py`, then encode the measured default threshold and runner-up margin with regression expectations in `Public/Stet/Packages/StetEngine/Tests/StetASRTests/SpeakerEmbeddingRecognizerTests.swift`
- [ ] T028 [US1] Run the complete P1 automated and manual acceptance matrix and record measured gate/label results in `specs/009-passive-speech-gate/quickstart.md`

**Checkpoint**: User Story 1 works without the hotkey: unrelated office speech creates no entry, while an owner-involved conversation produces one ordered, labeled, unrewritten history entry.

---

## Phase 4: User Story 2 - Hotkey-controlled active transcription (Priority: P2)

**Goal**: Make active hotkey capture atomically take ownership, accept every speaker, produce no duplicate passive interval, and return immediately to a fresh passive epoch.

**Independent Test**: Press the hotkey from armed, pending, and relevant states; verify pending audio is discarded, accepted passive audio seals before the boundary, all post-boundary audio goes only to active transcription, and release resumes passive without waiting for active ASR/rewrite.

### Tests for User Story 2

- [X] T029 [P] [US2] Add failing tests for hotkey-down/up actions from passive armed, pending, relevant, and active states plus stale-result suppression in `Public/Stet/StetMacTests/App/Workflows/MacDictationHotkeyInteractionTests.swift` and `Public/Stet/StetMacTests/App/Workflows/MacAppSessionControllerActionTests.swift`
- [X] T030 [P] [US2] Add failing tests that active Nano receives every completed hotkey interval, skips application speaker gating and precise batch trimming, resumes passive after capture stop, and never shares frame IDs with passive in `Public/Stet/StetMacTests/Core/Speech/ConfigurableSpeechServiceTests.swift` and `Public/Stet/StetMacTests/Core/Audio/Recording/MacRecordingFileSupportTests.swift`

### Implementation for User Story 2

- [X] T031 [US2] Route hotkey down through an atomic coordinator takeover that discards pending or seals relevant audio at the sample boundary, and route hotkey up to a new empty passive epoch in `Public/Stet/StetMac/App/Workflows/MacAppSessionController+Dictation.swift` and `Public/Stet/StetMac/Core/Speech/MacPassiveListeningCoordinator.swift`
- [X] T032 [US2] Keep the complete active interval independent of speaker identity, bypass precise post-capture VAD trimming for Nano, and signal passive resume as soon as capture stops rather than after ASR/rewrite in `Public/Stet/StetMac/Core/Speech/ConfigurableSpeechService.swift`
- [X] T033 [US2] Preserve existing tap/hold/latch hotkey behavior while adding passive ownership transitions in `Public/Stet/StetMac/App/Workflows/MacDictationHotkeyInteraction.swift`
- [X] T034 [US2] Run the focused hotkey, capture-boundary, speech-service, and duplicate-interval tests through `Public/Stet/Makefile`

**Checkpoint**: User Story 2 independently demonstrates deterministic active capture for any speaker and immediate clean return to passive mode.

---

## Phase 5: User Story 3 - Consistent engine behavior across Mac and iPhone (Priority: P3)

**Goal**: Default Mac to FunASR Nano, default iPhone to FunASR Realtime, preserve supported explicit Mac choices, remove SenseVoice choices/resources, and keep equivalent active start/stop semantics.

**Independent Test**: Reset and migrate preferences on both platforms, verify the expected engine, complete one active capture on each, confirm engine-owned boundary behavior, and confirm no SenseVoice choice remains.

### Tests for User Story 3

- [X] T035 [P] [US3] Add failing public-contract tests for supported enum cases, Nano default, retired raw-value migration, and preserved supported choices in `Public/Stet/Packages/StetEngine/Tests/StetCoreTests/StoredTranscriptionEngineTests.swift` and `Public/Stet/StetMacTests/Core/DictationPipeline/DictationPipelineTests.swift`
- [X] T036 [P] [US3] Update failing Mac settings and onboarding tests to expect Nano preparation/defaults and no SenseVoice option in `Public/Stet/StetMacTests/Features/MacShell/AudioSetting/MacAudioSettingsViewModelTests.swift` and `Public/Stet/StetMacTests/Features/Onboarding/OnboardingViewModelTests.swift`
- [X] T037 [P] [US3] Update failing iPhone tests for Realtime new/reset/retired defaults, direct Realtime composition, no local-model section, and unchanged active lifecycle in `Private/StetMobile/StetMobileTests/FunASRSettingsTests.swift`, `Private/StetMobile/StetMobileTests/RewriteSettingsViewModelTests.swift`, and `Private/StetMobile/StetMobileTests/DictationSessionCoordinatorTests.swift`

### Implementation for User Story 3

- [X] T038 [US3] Remove the public SenseVoice cases, add the Nano onboarding engine case, set the stored Mac default, and persist retired raw values as Nano in `Public/Stet/Packages/StetEngine/Sources/StetCore/StoredTranscriptionEngine.swift`, `Public/Stet/Packages/StetEngine/Sources/StetCore/TranscriptionEngine.swift`, and `Public/Stet/StetMac/Shared/Utilities/UserDefaultsModelStorage.swift`
- [X] T039 [US3] Remove SenseVoice branches and model UI, make onboarding prepare Nano, and preserve Parakeet/Whisper explicit choices in `Public/Stet/StetMac/Core/DictationPipeline/DictationPipelineFactory.swift`, `Public/Stet/StetMac/Shared/Utilities/TranscriptionLanguageRouting.swift`, `Public/Stet/StetMac/Features/Onboarding/OnboardingViewModel.swift`, `Public/Stet/StetMac/Features/Onboarding/Steps/OnboardingLanguageStep.swift`, `Public/Stet/StetMac/Features/Onboarding/Components/OnboardingVisualPanel.swift`, `Public/Stet/StetMac/Features/MacShell/AudioSetting/MacAudioSettingsViewModel.swift`, and `Public/Stet/StetMac/Features/MacShell/AudioSetting/MacAudioSettingsView.swift`
- [X] T040 [US3] Remove retired Mac SenseVoice services/preferences and update remaining MCP engine wording in `Public/Stet/StetMac/Core/SenseVoice/SenseVoiceShared.swift`, `Public/Stet/StetMac/Core/SenseVoice/SherpaOnnxSenseVoiceModelManager.swift`, `Public/Stet/StetMac/Core/SenseVoice/SherpaOnnxSenseVoiceTranscriptionService.swift`, `Public/Stet/StetMac/Shared/Utilities/MacPreferences.swift`, `Public/Stet/StetMac/Core/MCP/MCPTranscriptionCoordinator.swift`, and `Public/Stet/StetMac/Core/MCP/StetMCPProtocolServer.swift`
- [X] T041 [P] [US3] Make iPhone settings migrate to the single Realtime engine, compose `FunASRRealtimeEngine` directly, remove selectable/local-model management, and remove the engine/local-model picker UI in `Private/StetMobile/StetMobile/Core/Settings/LocalDictationModelManager.swift`, `Private/StetMobile/StetMobile/App/StetMobileApp.swift`, `Private/StetMobile/StetMobile/Core/Dictation/DictationSessionCoordinator.swift`, `Private/StetMobile/StetMobile/Features/Settings/ViewModels/RewriteSettingsViewModel.swift`, and `Private/StetMobile/StetMobile/Features/Settings/Views/RewriteSettingsView.swift`
- [X] T042 [US3] Remove retired shared SenseVoice ASR implementation files while preserving the Sherpa package and speaker-embedding wrapper in `Public/Stet/Packages/StetEngine/Sources/StetASR/SenseVoiceModelManager.swift`, `Public/Stet/Packages/StetEngine/Sources/StetASR/SenseVoiceFileTranscriber.swift`, `Public/Stet/Packages/StetEngine/Sources/StetASR/SherpaOnnxASREngine.swift`, `Public/Stet/Packages/StetEngine/Sources/StetASR/ASRModelManager.swift`, and `Public/Stet/Packages/StetEngine/Package.swift`
- [X] T043 [US3] Replace remaining user-visible SenseVoice preview/test engine names with FunASR Realtime while leaving generic view-model renames out of scope in `Private/StetMobile/StetMobile/App/ContentView.swift` and `Private/StetMobile/StetMobileTests/AppViewModelTests.swift`
- [X] T044 [US3] Run Mac engine/pipeline/onboarding tests and the iPhone Realtime/settings/coordinator tests through `Public/Stet/Makefile` and `Makefile`

**Checkpoint**: User Story 3 independently proves correct defaults/migration, equivalent active capture lifecycle, and complete removal of selectable SenseVoice behavior.

---

## Phase 6: Polish & Cross-Cutting Validation

**Purpose**: Validate the integrated feature's privacy, recovery, energy, memory, and repository boundaries without expanding scope.

- [X] T045 [P] Add an eight-hour synthetic mixed-session regression covering bounded RAM, zero other-only ASR entries, failure recovery, and disjoint active/passive sample ranges in `Public/Stet/StetMacTests/Core/Speech/MacPassiveListeningCoordinatorTests.swift`
- [X] T046 [P] Add regression checks that no raw enrollment/pending audio, centroid, model payload, or private iOS source enters history export or the public projection in `Public/Stet/Packages/StetEngine/Tests/StetCoreTests/DictationHistoryServiceTests.swift` and `Makefile`
- [ ] T047 Run the eight-hour Instruments Energy/Memory validation, verify temporary-file and Keychain cleanup, and record measurements in `specs/009-passive-speech-gate/quickstart.md`
- [X] T048 Run formatting, lint, Mac tests/build, iOS build, and public-boundary validation using `Makefile` and `Public/Stet/Makefile`

---

## Phase 7: v0.5.5 Capture Reliability

**Purpose**: Prevent passive lifecycle events from interrupting active dictation and expose the requested passive controls.

- [X] T049 Add regressions for deferred/coalesced passive restarts, producer-side capture liveness, and recovery after empty Nano turns in `Public/Stet/StetMacTests/Core/Speech/`
- [X] T050 Serialize passive start/stop/restart, defer teardown during active capture, gate readiness on the first frame, and recover stalled capture in `Public/Stet/StetMac/Core/Speech/`
- [X] T051 Add a persisted default-on passive transcription switch and a visible known-speaker name field in `Public/Stet/StetMac/Features/MacShell/AudioSetting/`
- [X] T052 Run the release gates, bump to v0.5.5 (5005), publish the public projection, and verify the GitHub release assets

---

## Phase 8: v0.5.6 Speaker Gate Recalibration

**Purpose**: Reduce owner false rejects by extracting enrollment embeddings from VAD-voiced audio only, lowering the default match threshold, and forcing re-enrollment of legacy 0.70 profiles.

- [X] T053 Restrict enrollment embeddings to VAD-approved speech, default the owner match threshold to 0.60, mark 0.70 profiles for reenrollment, and log owner verification results
- [ ] T054 Run the release gates, bump to v0.5.6 (5006), publish the public projection, and verify the GitHub release assets

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: No dependencies; T001 and T002 can run in parallel.
- **Phase 2 (Foundational)**: Depends on Phase 1 and blocks User Stories 1 and 2. Contract/capture tests T003 and T004 are written first and may run in parallel; implementations then proceed T005 → T006 and T007 → T008 → T009.
- **User Story 1 (P1)**: Depends on Phase 2. Tests T011–T016 are written first. T017, T018, and T019 may then run in parallel; T020 depends on T017/T018; T021 depends on T017–T019; T022–T026 follow T021; calibration and acceptance are T027–T028.
- **User Story 2 (P2)**: Depends on the Phase 2 capture boundary and the User Story 1 coordinator through T021. Tests T029–T030 precede T031–T033; T034 validates the story.
- **User Story 3 (P3)**: Its tests T035–T037 may begin after Phase 1. T038 precedes T039; T040 follows removal of Mac references in T039; T041 can run in parallel with Mac work; T042 follows T017, T040, and T041 so the Sherpa embedding surface remains intact; T043 follows T041.
- **Phase 6 (Polish)**: Depends on all selected user stories. T045 and T046 can run in parallel; T047 and T048 finish validation.

### User Story Completion Order

```text
Setup → Foundation → US1 (passive MVP) → US2 (active takeover)
                          └──────────────→ US3 (engine defaults/removal)
US1 + US2 + US3 → Cross-cutting validation
```

- **User Story 1** is the MVP and establishes the coordinator consumed by User Story 2.
- **User Story 2** depends on User Story 1 only for passive-state ownership; its active transcription assertions remain independently testable.
- **User Story 3** is behaviorally independent, except shared SenseVoice deletion waits for the User Story 1 speaker-embedding wrapper so Sherpa is not removed accidentally.

### Parallel Opportunities

- Setup: T001 and T002.
- Foundation: T003 and T004; then the history branch T005–T006 can proceed alongside capture branch T007–T009.
- User Story 1 tests: T011–T016; implementations T017, T018, and T019.
- User Story 2 tests: T029 and T030.
- User Story 3 tests: T035–T037; iPhone implementation T041 alongside Mac T038–T040 after its test exists.
- Polish tests: T045 and T046.

## Parallel Example: User Story 1

```text
Task T017: Implement CAMPPlus speaker embedding in Public/Stet/Packages/StetEngine/Sources/StetASR/SpeakerEmbeddingRecognizer.swift
Task T018: Implement local-only profiles in Public/Stet/StetMac/Core/Speech/SpeakerProfileStore.swift
Task T019: Implement FluidAudio VAD/Sortformer in Public/Stet/StetMac/Core/FluidAudio/FluidAudioPassiveSpeechAnalyzer.swift
```

## Parallel Example: User Story 3

```text
Task T039: Update Mac defaults/onboarding/settings under Public/Stet/
Task T041: Update Realtime-only iPhone composition under Private/StetMobile/
```

---

## Implementation Strategy

### MVP First

1. Complete Setup and Foundational phases.
2. Complete User Story 1 through T028.
3. Stop and validate that owner-involved conversations are captured while silence and other-only speech remain untranscribed.

### Incremental Delivery

1. **US1**: Passive relevance gate, diarization, identities, and history.
2. **US2**: Atomic hotkey takeover and immediate passive resume.
3. **US3**: Platform defaults and SenseVoice removal.
4. **Polish**: Long-run energy/privacy/public-boundary validation.

## Notes

- Do not commit ONNX/Core ML model payloads, recorded voice corpora, temporary audio, or downloaded frameworks.
- Do not persist or log enrollment clips, pending audio, or per-clip embeddings.
- Keep private iPhone files under `Private/StetMobile/`; never copy them into `Public/Stet/`.
- Preserve unrelated worktree changes, including `Public/Stet/scripts/speaker_verification_probe.py` if it remains user-owned/untracked.
- `[P]` tasks touch distinct files at their starting dependency point; never run Git index-writing commands in parallel.
