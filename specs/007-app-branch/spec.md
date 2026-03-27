# Feature Specification: App Branch

**Feature Branch**: `007-app-branch`  
**Created**: 2026-03-27  
**Status**: Draft  
**Input**: User description: "Document the app-branch feature against the current implementation. Prioritize Constitution -> current implementation -> old .kiro docs. If .kiro conflicts with implementation, follow implementation and record the difference in plan.md."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Resolve the Current Frontmost App (Priority: P1)

As the runtime, I can synchronously ask which app is currently frontmost so downstream features can branch on the active app context.

**Why this priority**: Everything else in this feature depends on having a reliable current-app snapshot.

**Independent Test**: Inject a known workspace snapshot and read the current app without starting continuous monitoring.

**Acceptance Scenarios**:

1. **Given** a frontmost app with a bundle identifier, localized name, process identifier, and host-app flag, **When** the current app is queried, **Then** the feature returns a matching snapshot.
2. **Given** the frontmost app changes in the workspace snapshot, **When** the current app is queried again, **Then** the returned snapshot reflects the new frontmost app.
3. **Given** there is no frontmost app or the frontmost app has no bundle identifier, **When** the current app is queried, **Then** the feature returns `nil`.
4. **Given** the frontmost app does not provide a localized name, **When** the snapshot is resolved, **Then** the feature still returns a usable app label for downstream use.

---

### User Story 2 - Observe App Switches in Real Time (Priority: P1)

As the runtime, I can subscribe to app activation changes so dependent features update when the user switches applications.

**Why this priority**: The app signal is only useful if consumers can react to changes without manual polling.

**Independent Test**: Start monitoring with a fake workspace, observe the initial snapshot, then simulate an activation change and verify that observers receive the updated app.

**Acceptance Scenarios**:

1. **Given** monitoring has started, **When** the feature initializes, **Then** the current app snapshot is published to registered observers.
2. **Given** monitoring is active, **When** the user switches to a different app, **Then** all registered observers receive the new app snapshot.
3. **Given** multiple observers are registered, **When** the foreground app changes, **Then** each observer receives the same update.
4. **Given** monitoring has been stopped, **When** the workspace changes again, **Then** no further observer notifications are delivered.

---

### User Story 3 - Ignore the Host App When Needed (Priority: P2)

As the runtime, I can exclude the app's own host process or another bundle identifier so detection focuses on the target app the user is actually working in.

**Why this priority**: Downstream dictation behavior needs a way to skip the app itself when the app becomes frontmost.

**Independent Test**: Configure an excluded bundle identifier, switch the workspace to that app, and verify that the detected app falls back to the previous non-excluded app or `nil`.

**Acceptance Scenarios**:

1. **Given** an excluded bundle identifier matches the frontmost app and a more recent non-excluded app exists, **When** the current app is queried, **Then** the most recent non-excluded app is returned.
2. **Given** an excluded bundle identifier matches the frontmost app and no previous non-excluded app exists, **When** the current app is queried, **Then** the feature returns `nil`.
3. **Given** the excluded bundle identifier changes, **When** the current app is queried again, **Then** the detected target app reflects the new exclusion rule.

---

### User Story 4 - Route Cleanup Behavior by App Type (Priority: P2)

As the runtime, I can classify the active app as human-oriented or AI-oriented so downstream cleanup behavior can adapt to the current destination.

**Why this priority**: The current implementation already uses the foreground app signal to steer cleanup behavior, so the spec should capture that branching rule.

**Independent Test**: Resolve known AI tools and unknown apps and verify that the active-app classification matches the expected cleanup-routing category.

**Acceptance Scenarios**:

1. **Given** the active app matches a known AI tool name or bundle identifier, **When** the app is classified, **Then** the feature marks it as AI-oriented.
2. **Given** the active app does not match a known AI tool, **When** the app is classified, **Then** the feature marks it as human-oriented.
3. **Given** dictation cleanup depends on the active app classification, **When** the active app is AI-oriented, **Then** downstream cleanup behavior can switch to the AI-oriented cleanup style.

---

### Edge Cases

- What happens when the frontmost application is unavailable?
- What happens when the frontmost application has no bundle identifier?
- What happens when the frontmost application has no localized name?
- What happens when the excluded app is frontmost and there is no earlier non-excluded app to fall back to?
- What happens when observers are added or removed while monitoring is active?
- What happens when app switches happen in rapid succession?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The feature MUST provide synchronous access to the current frontmost app snapshot.
- **FR-002**: The current app snapshot MUST include a bundle identifier, a readable app name, a process identifier, and whether the app is the host application.
- **FR-004**: The feature MUST allow consumers to start and stop continuous monitoring of foreground app changes.
- **FR-005**: The feature MUST support multiple concurrent observers.
- **FR-006**: The feature MUST notify registered observers when the frontmost app changes.
- **FR-007**: Starting monitoring MUST make the current app state available to observers without requiring manual polling.
- **FR-008**: Stopping monitoring MUST prevent further observer notifications and MUST be safe to call more than once.
- **FR-009**: The feature MUST allow a bundle identifier to be excluded from detection.
- **FR-010**: When the excluded app is frontmost, the feature MUST return the most recent non-excluded app when one exists, otherwise `nil`.
- **FR-011**: The feature MUST support excluding the host application bundle identifier.
- **FR-012**: The feature MUST classify the active app as human-oriented or AI-oriented for downstream cleanup routing.
- **FR-013**: The feature MUST treat known AI tools as AI-oriented and unknown apps as human-oriented.
- **FR-014**: The feature MUST remain usable without persisting app-branch history across launches.

### Key Entities *(include if feature involves data)*

- **Foreground App Snapshot**: The current detected frontmost application, including bundle identifier, display name, process identifier, and host-app status.
- **Observer Registration**: A registered callback and its identifier for receiving foreground-app updates.
- **Excluded Bundle Identifier**: The bundle identifier that should be skipped when resolving the detected target app.
- **App Audience Classification**: The derived app type used to decide whether downstream cleanup behavior should use human-oriented or AI-oriented cleanup rules.
- **Monitor Runtime State**: The transient in-memory state that tracks monitoring status, exclusions, last detected app, and registered observers.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A developer can query the current frontmost app snapshot synchronously in the test harness without starting a separate polling loop.
- **SC-002**: Starting monitoring produces an initial app snapshot and subsequent activation changes are observable in the current test suite.
- **SC-003**: Excluding the host app causes the detected app to fall back to the previous non-excluded app when one exists, and to `nil` otherwise.
- **SC-004**: Known AI tools resolve to AI-oriented classification and can drive AI-oriented downstream cleanup behavior.
- **SC-005**: The feature does not persist app-branch state across app relaunches.
- **SC-006**: The documented behavior matches the current implementation, with any intentional deviations from the old `.kiro` draft called out in `plan.md`.

## Assumptions

- The feature is a macOS-only runtime signal inside the main app, not a standalone app or service.
- Foreground app detection is event-driven through workspace activation notifications rather than manual polling.
- The app-branch signal is consumed internally by the app's dictation and app-session flows rather than exposed as a user-facing screen.
- Heuristic AI/human classification is acceptable for prompt routing as long as the current implementation remains consistent.
- No persisted app-branch history is required for v1.
