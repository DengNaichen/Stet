# Requirements Document: Permission Management

## Overview

This document defines the requirements for improving permission management in Stet on macOS.

Stet already depends on microphone access and text injection access for its primary dictation workflow. Today, when the user triggers a permission-dependent action and required permissions are missing, the action can fail without sufficient visible guidance.

This specification focuses on one concrete product goal:

- when a user tries to use a runtime feature and Stet cannot proceed because permissions are missing, Stet shall show a small standalone recovery window

This specification does not attempt to define a full permission dashboard for runtime use.

---

## Glossary

- **Microphone Access**: macOS permission that allows Stet to capture audio input for dictation.
- **Text Injection Access**: The system access Stet needs in order to insert dictated text into other applications.
- **Runtime Permission-Failure Window**: A small standalone window shown when the user tries to use a permission-dependent feature but the action cannot proceed.
- **Silent Failure**: A failed user action that does not provide a visible explanation or recovery path.

---

## Core Principles

- Microphone access and text injection access are both required for the primary dictation workflow.
- The application SHALL not silently fail when a required permission is missing.
- The runtime recovery UI SHALL be minimal and action-oriented.
- The runtime recovery UI SHALL be separate from onboarding.
- The runtime recovery UI SHALL not interrupt active recording or processing.

---

## Requirements

### Requirement 1: Permission Onboarding

**User Story:** As a new user, when I first launch the application, I want to see a clear explanation of the required permissions, so that I understand why Stet needs them and how to grant them.

#### Acceptance Criteria

1. THE onboarding flow SHALL include a dedicated permission step.
2. THE onboarding permission step SHALL explain why microphone access is required for audio capture.
3. THE onboarding permission step SHALL explain why text injection access is required for inserting dictated text into other applications.
4. THE onboarding permission step SHALL provide recovery actions for the required permissions.
5. THE onboarding flow SHALL NOT allow the user to continue past the permission step until both required permissions are available.
6. THE permission copy SHALL be localizable and SHALL support presentation in the user's system language.

---

### Requirement 2: Runtime Permission Failure Feedback

**User Story:** As a user, when I attempt to start a permission-dependent action without the required permissions, I want immediate and actionable feedback, so that I understand why the action could not start and what to do next.

#### Acceptance Criteria

1. WHEN the user triggers dictation via hotkey AND required permissions are missing, THE system SHALL present a runtime permission-failure window.
2. WHEN the user triggers dictation via a primary recording action AND required permissions are missing, THE system SHALL present a runtime permission-failure window.
3. THE runtime permission-failure window SHALL contain a short explanation that the action could not start because required permissions are missing.
4. THE runtime permission-failure window SHALL contain one primary recovery action for microphone access.
5. THE runtime permission-failure window SHALL contain one primary recovery action for text injection access.
6. THE runtime permission-failure window SHALL NOT be presented again as a duplicate if an equivalent window is already visible.
7. THE runtime permission-failure window SHALL NOT interrupt an active recording or processing session.

---

### Requirement 3: Runtime Recovery Actions

**User Story:** As a user, when a runtime action is blocked by missing permissions, I want direct recovery actions in the failure window, so that I can quickly restore access.

#### Acceptance Criteria

1. THE microphone recovery action SHALL trigger the appropriate existing application path for microphone recovery.
2. THE text injection recovery action SHALL trigger the appropriate existing application path for text injection recovery.
3. FOR microphone access, THE application SHALL make a best effort to request access in-app when possible, or open the relevant System Settings area when required.
4. FOR text injection access, THE application SHALL make a best effort to trigger the existing text injection recovery path used by the application.
5. IF macOS does not support precise deep-linking to the exact settings pane on a supported OS version, THE application SHALL open the closest relevant System Settings area available.

---

### Requirement 4: Permission State Refresh

**User Story:** As a user, when I change permissions in System Settings and return to Stet, I want the app to refresh immediately, so that I do not need to restart it.

#### Acceptance Criteria

1. THE application SHALL refresh permission state when it becomes active after the user returns from System Settings.
2. THE application SHALL refresh permission state before performing a permission-dependent runtime action.
3. WHEN permission state changes, THE onboarding UI and runtime permission-failure window SHALL update accordingly.
4. WHEN the runtime permission-failure window is visible AND all required permissions become available, THE window SHALL automatically close.
5. THE implementation SHALL NOT require an application restart to detect changed permissions.

---

### Requirement 5: Trigger Points

**User Story:** As a system, I want permission checks at the relevant runtime entry points, so that users receive consistent recovery feedback when an action cannot start.

#### Acceptance Criteria

1. THE system SHALL check required permissions when the user presses the dictation hotkey.
2. THE system SHALL check required permissions when the user invokes the primary Start Recording action.
3. THE system SHALL check required permissions before audio capture begins.
4. THE system SHALL present the runtime permission-failure window only for actions that cannot proceed because permissions are missing.
5. THE runtime permission-failure window SHALL NOT be presented while dictation state is not idle.

---

### Requirement 6: Runtime Window Behavior

**User Story:** As a user, I want the runtime permission-failure window to be visible and focused without being unnecessarily disruptive, so that I can resolve the problem and try again.

#### Acceptance Criteria

1. THE runtime permission-failure window SHALL be presented as a small, focused standalone window.
2. THE runtime permission-failure window SHALL remain visible above normal application content while it is active.
3. THE runtime permission-failure window SHALL be dismissible by the user.
4. WHEN the user dismisses the runtime permission-failure window without restoring permissions, THE application SHALL allow dismissal.
5. WHEN the user later triggers the same blocked action again, THE runtime permission-failure window SHALL reappear.
6. THE runtime permission-failure window SHALL contain one explanation text block and two primary recovery buttons.
7. THE runtime permission-failure window SHALL avoid presenting a full permission status panel in the MVP implementation.

---

## Non-Functional Requirements

### Usability

- Runtime permission messaging SHALL use clear, non-technical language.
- Recovery actions SHALL use descriptive labels.
- The runtime permission-failure window SHALL support keyboard navigation.
- Recovery messaging SHALL tell the user what to do next.

### Performance

- Permission evaluation during a dictation start attempt SHOULD feel immediate to the user.
- Runtime window presentation SHOULD occur without a noticeable delay after a blocked action.
- Permission refresh behavior SHALL avoid heavy background work while the app is inactive.

### Compatibility

- THE feature SHALL support macOS 12.0 and later.
- THE feature SHALL work with the existing SwiftUI and AppKit integration points in the macOS app.
- THE feature SHALL respect relevant system accessibility settings, including keyboard navigation and reduced motion where applicable.

---

## Out of Scope

The following are explicitly not included in this specification:

- A full runtime permission status dashboard
- Detailed runtime permission badges or state matrices
- Degraded dictation functionality when only some required permissions are granted
- Menu bar indicators for permission state
- Automatic retry of a previously blocked action after permissions are restored
- Dock icon status for permissions
- Notification Center alerts for permission issues
- Telemetry or analytics for permission prompts
- Guaranteeing exact System Settings deep links on every macOS version
