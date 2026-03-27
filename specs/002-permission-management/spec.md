# Feature Specification: Permission Management

**Feature Branch**: `002-permission-management`  
**Created**: 2026-03-27  
**Status**: Draft  
**Input**: Existing permission-management behavior already implemented in the current codebase

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Blocked Runtime Action Recovery (Priority: P1)

As a user, when I trigger dictation or another permission-dependent action without the required permissions, I want an immediate recovery surface, so that the app does not fail silently.

**Why this priority**: This is the primary user-facing failure mode the feature exists to solve.

**Independent Test**: Trigger the hotkey or primary dictation action with permissions missing and verify that a standalone permission-failure window appears.

**Acceptance Scenarios**:

1. **Given** required permissions are missing, **When** I trigger dictation from the hotkey, **Then** Stet shows a runtime permission-failure window.
2. **Given** required permissions are missing, **When** I trigger the primary recording action, **Then** Stet shows the same runtime permission-failure window instead of starting recording.

---

### User Story 2 - Onboarding Permission Guidance (Priority: P2)

As a new user, when I reach the onboarding permission step, I want to understand why microphone and input control access are required, so that I can grant them before continuing.

**Why this priority**: The onboarding step prevents confusion before the app reaches its primary workflow.

**Independent Test**: Launch onboarding, navigate to the permission step, and verify that the step explains the required permissions and blocks continuation until both are available.

**Acceptance Scenarios**:

1. **Given** onboarding is active, **When** I reach the permission step, **Then** I see microphone and input control access guidance.
2. **Given** one or both required permissions are missing, **When** I try to continue past the permission step, **Then** the app keeps me on that step.

---

### User Story 3 - Permission Recovery Actions (Priority: P2)

As a user, when permission access is missing, I want direct recovery actions, so that I can restore access without leaving the app flow.

**Why this priority**: Recovery actions are the shortest path back to a working dictation workflow.

**Independent Test**: Use the onboarding permission step or runtime permission-failure window and verify that the microphone and input control actions route to the existing recovery paths.

**Acceptance Scenarios**:

1. **Given** microphone access is not yet granted, **When** I choose the microphone recovery action, **Then** Stet requests access in-app when possible or opens System Settings when needed.
2. **Given** input control access is not available, **When** I choose the input control recovery action, **Then** Stet opens the existing accessibility/input-control recovery path.

---

### User Story 4 - Permission Refresh After Settings Changes (Priority: P3)

As a user, when I change permissions in System Settings and return to Stet, I want the app to refresh immediately, so that I do not need to restart it.

**Why this priority**: This keeps the app responsive to system permission changes, but it depends on the core recovery experience.

**Independent Test**: Change permissions in System Settings, return to the app, and verify that permission state updates and any visible runtime gate closes automatically.

**Acceptance Scenarios**:

1. **Given** the runtime permission-failure window is visible, **When** the required permissions become available, **Then** the window closes automatically.
2. **Given** I return to Stet from System Settings, **When** the app becomes active, **Then** permission state refreshes without a restart.

### Edge Cases

- What happens when the same blocked action is triggered again while the runtime permission-failure window is already visible?
- What happens when permissions are granted while dictation is idle versus while recording or processing is already active?
- How does the app behave when microphone permission cannot be requested in-app and must be resolved through System Settings?
- What happens when onboarding is already complete and only runtime permission recovery is needed?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The onboarding flow MUST include a dedicated permission step that covers microphone access and input control access.
- **FR-002**: The onboarding permission step MUST explain why each required permission is needed for the dictation workflow.
- **FR-003**: The onboarding permission step MUST provide recovery actions for microphone access and input control access.
- **FR-004**: The onboarding flow MUST prevent the user from continuing past the permission step until the required permissions are available.
- **FR-005**: The app MUST present a standalone runtime permission-failure window when the user triggers a permission-dependent action and the action cannot start because permissions are missing.
- **FR-006**: The runtime permission-failure window MUST remain separate from onboarding and MUST stay minimal rather than becoming a full permission dashboard.
- **FR-007**: The runtime permission-failure window MUST not interrupt an active recording or processing session.
- **FR-008**: The app MUST check permission state when the app becomes active and before permission-dependent actions start.
- **FR-009**: The runtime permission-failure window MUST close automatically when required permissions become available again.
- **FR-010**: The runtime permission-failure window MUST not be duplicated when an equivalent window is already visible.
- **FR-011**: The microphone recovery action MUST request access in-app when possible and otherwise open the appropriate System Settings location.
- **FR-012**: The input control recovery action MUST call the app's existing accessibility/input-control recovery path.
- **FR-013**: Permission state presented in the UI MUST reflect the current system state rather than a stale cached permission grant.

### Key Entities *(include if feature involves data)*

- **PermissionStatus**: The current status of a permission signal, including allowed, not requested, needs access, and unavailable states.
- **PermissionSnapshot**: The current combined permission state for microphone access and input control access, plus the derived `hasRequiredPermissions` result.
- **OnboardingPermissionStep**: The onboarding surface that presents permission guidance and gates continuation.
- **RuntimePermissionGate**: The standalone recovery surface shown when a permission-dependent action cannot start.
- **PermissionRecoveryAction**: A user-visible action that requests access or opens the relevant system recovery path.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: When required permissions are missing, blocked dictation attempts surface a visible recovery window instead of failing silently.
- **SC-002**: The onboarding permission step prevents continuation until required permissions are available.
- **SC-003**: Permission changes made in System Settings are reflected in Stet after the app becomes active again, without requiring a restart.
- **SC-004**: Repeated blocked actions do not create duplicate runtime permission windows while one is already visible.
- **SC-005**: The runtime recovery surface remains a lightweight recovery UI rather than a full permission dashboard.

## Assumptions

- The current product term for the second required permission is "input control" rather than a separate long-term permission dashboard.
- Permission grant state is queried from the system and is not treated as a user-editable local preference.
- The runtime permission-failure window is intentionally minimal and is not meant to replace onboarding.
- The current project target is macOS 26.0+, which is the version this feature documentation aligns to.
