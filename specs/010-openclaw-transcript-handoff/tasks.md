# Tasks: OpenClaw Transcript Handoff

**Input**: Design documents from `/specs/010-openclaw-transcript-handoff/`
**Prerequisites**: `plan.md` (required), `spec.md` (required for user stories), `research.md`, `data-model.md`, `contracts/`

**Organization**: Tasks are grouped by user story so each route can be implemented and tested independently.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel
- **[Story]**: Which user story the task belongs to
- Include exact file paths in descriptions

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Establish the new OpenClaw route boundary and the hotkey plumbing needed by all stories.

- [x] T001 [P] Create the OpenClaw integration scaffold in `apps/mac/Stet/Core/OpenClaw/OpenClawAgentHandoffService.swift`, `apps/mac/Stet/Core/OpenClaw/OpenClawCLI.swift`, and `apps/mac/Stet/Core/OpenClaw/OpenClawAgentHandoffError.swift`
- [x] T002 [P] Extend hotkey identity and defaults in `apps/mac/Stet/Shared/Models/HotKeyPreferences.swift` and `apps/mac/Stet/Core/Hotkey/HotkeyBindings.swift` so the OpenClaw route has its own binding name
- [x] T003 [P] Extend the hotkey registration protocol and live registrar in `apps/mac/Stet/App/Lifecycle/MacAppContracts.swift` and `apps/mac/Stet/App/Workflows/KeyboardShortcutsHotkeyRegistrar.swift` so the app can register a second global hotkey
- [x] T004 Prepare route-aware workflow plumbing in `apps/mac/Stet/App/Workflows/MacAppSessionController.swift`, `apps/mac/Stet/App/Workflows/MacDictationWorkflowController.swift`, and `apps/mac/Stet/Features/Dictation/DictationViewModel.swift`

**Checkpoint**: Hotkey and routing foundations are ready for feature work.

---

## Phase 2: User Story 1 - Hand off transcript to OpenClaw via AI route (Priority: P1)

**Goal**: A second shortcut captures speech and sends the rewritten finalized transcript to local OpenClaw through the AI route instead of injecting into the focused app.

**Independent Test**: Trigger the OpenClaw hotkey, complete dictation, and verify the transcript is handed off locally without text injection into the active app.

### Tests for User Story 1

- [x] T005 [P] [US1] Add unit tests for OpenClaw CLI handoff success and failure cases in `apps/mac/StetTests/Core/OpenClaw/OpenClawAgentHandoffServiceTests.swift`
- [x] T006 [P] [US1] Add workflow tests that prove the OpenClaw route does not use human input injection in `apps/mac/StetTests/App/Workflows/MacAppSessionControllerActionTests.swift` and `apps/mac/StetTests/App/Workflows/MacDictationWorkflowControllerTests.swift`
- [x] T007 [P] [US1] Add rewrite-failure coverage in `apps/mac/StetTests/Features/Dictation/DictationViewModelTests.swift` so the AI pipeline failure is distinct from OpenClaw handoff failure

### Implementation for User Story 1

- [x] T008 [US1] Implement the OpenClaw CLI runner and local-only handoff logic in `apps/mac/Stet/Core/OpenClaw/OpenClawCLI.swift` and `apps/mac/Stet/Core/OpenClaw/OpenClawAgentHandoffService.swift`
- [x] T009 [US1] Thread the OpenClaw route through capture completion in `apps/mac/Stet/App/Workflows/MacDictationWorkflowController.swift` and `apps/mac/Stet/App/Workflows/MacAppSessionController.swift`
- [x] T010 [US1] Add distinct error mapping for rewrite failure versus OpenClaw handoff failure in `apps/mac/Stet/Features/Dictation/DictationFailure.swift` and `apps/mac/Stet/Features/Dictation/DictationViewModel.swift`
- [x] T011 [US1] Ensure the OpenClaw route never mirrors output into the capsule UI in `apps/mac/Stet/App/Workflows/MacAppSessionController.swift`

**Checkpoint**: The OpenClaw hotkey path is functional and isolated from the human injection path.

---

## Phase 3: User Story 2 - Preserve the existing dictation flow (Priority: P2)

**Goal**: The original dictation shortcut continues to inject text into the current focused app exactly as before.

**Independent Test**: Trigger the original dictation shortcut and verify injected text still lands in the focused input field.

### Tests for User Story 2

- [x] T012 [P] [US2] Add regression tests for the original dictation hotkey path in `apps/mac/StetTests/App/Workflows/MacAppSessionControllerActionTests.swift`
- [x] T013 [P] [US2] Add regression tests for the existing dictation completion and injection route in `apps/mac/StetTests/Core/DictationPipeline/DictationPipelineTests.swift`

### Implementation for User Story 2

- [x] T014 [US2] Preserve the existing human injection route while introducing route selection in `apps/mac/Stet/App/Workflows/MacDictationWorkflowController.swift` and `apps/mac/Stet/Core/TextInput/TextInjectionService.swift`
- [x] T015 [US2] Keep the current panel and capture lifecycle unchanged for the original shortcut in `apps/mac/Stet/App/Workflows/MacAppSessionController.swift`

**Checkpoint**: The original dictation shortcut still behaves exactly as before.

---

## Phase 4: User Story 3 - Make the OpenClaw route discoverable (Priority: P3)

**Goal**: Users can see, change, and persist the OpenClaw shortcut independently of the primary dictation shortcut.

**Independent Test**: Open settings, confirm the OpenClaw shortcut is visible and labeled, change it, and verify the change persists.

### Tests for User Story 3

- [ ] T016 [P] [US3] Add settings UI coverage for two independent hotkey recorders in `apps/mac/StetTests/Features/MacShell/MacDictationCommandsViewModelTests.swift` and `apps/mac/StetTests/App/Workflows/MacAppSessionControllerSettingsTests.swift`

### Implementation for User Story 3

- [ ] T017 [P] [US3] Add the OpenClaw recorder and label to the hotkey settings UI in `apps/mac/Stet/Features/MacShell/HotKeySetting/MacHotkeySettingsView.swift` and `apps/mac/Stet/Features/MacShell/HotKeySetting/MacHotKeySettingsSectionView.swift`
- [ ] T018 [US3] Update settings search/discoverability text so the OpenClaw route is easy to find in `apps/mac/Stet/Features/MacShell/Setting/MacSettingsView.swift`
- [ ] T019 [US3] Wire the second shortcut to its own persisted `KeyboardShortcuts.Name` so it saves independently of the primary dictation shortcut in `apps/mac/Stet/Core/Hotkey/HotkeyBindings.swift` and `apps/mac/Stet/App/Workflows/KeyboardShortcutsHotkeyRegistrar.swift`

**Checkpoint**: Users can discover and change the OpenClaw shortcut independently.

---

## Phase 5: Polish & Cross-Cutting Concerns

**Purpose**: Tighten integration, validate behavior, and remove any accidental coupling between the routes.

- [x] T020 [P] Run focused build and test validation for the changed macOS targets, then fix any integration issues in `apps/mac/StetTests/` and `apps/mac/StetUITests/`
- [ ] T021 [P] Review the capsule/OpenClaw boundary and clean up any leftover assumptions in `apps/mac/Stet/App/Workflows/MacAppSessionController.swift`, `apps/mac/Stet/Features/Dictation/DictationViewModel.swift`, and `apps/mac/Stet/Features/Dictation/DictationFailure.swift`

---

## Dependencies & Execution Order

### Phase Dependencies

- Setup must complete before user story work starts.
- User Story 1 is the MVP route and should land first.
- User Story 2 depends on the shared routing and hotkey scaffolding being in place, but must remain independently testable.
- User Story 3 depends on the hotkey model existing and can be finished after the route plumbing is stable.
- Polish depends on the user story work being complete.

### User Story Dependencies

- **User Story 1**: No dependency on the other stories.
- **User Story 2**: Can be validated after the shared routing scaffolding, but should not require the new OpenClaw UI.
- **User Story 3**: Can be implemented after the hotkey scaffolding exists and the second route is named.

### Within Each User Story

- Tests should be added before implementation where practical.
- Keep the OpenClaw route separate from the human injection route.
- Preserve the existing dictation completion flow unless a task explicitly narrows it.

### Parallel Opportunities

- Setup tasks marked `[P]` can be worked on in parallel.
- User Story 1 tests can run in parallel with each other.
- User Story 2 tests can run in parallel with each other.
- User Story 3 test and UI tasks can be split across settings and hotkey files.

---

## Implementation Strategy

### MVP First

1. Complete Setup.
2. Complete User Story 1.
3. Validate the OpenClaw handoff path end to end.
4. Then finish the regression work for the existing dictation route.
5. Finally, add the settings affordance and persistence for the second hotkey.
