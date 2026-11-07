# Feature Specification: Audio Device Management

**Feature Branch**: `001-audio-device-management`  
**Created**: 2026-03-26  
**Status**: Draft  
**Input**: Align the current macOS audio device management implementation with a product-focused specification

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Choose The Recording Microphone (Priority: P1)

As a user, I want to see the microphones Stet can use and choose the one I want, so that dictation records from the right input source.

**Why this priority**: Device visibility and selection are the core value of this feature. Without them, users cannot control audio input.

**Independent Test**: Open the audio device controls, confirm available microphones are listed, select a different microphone, and verify the selection changes immediately.

**Acceptance Scenarios**:

1. **Given** one or more microphones are available, **When** I open Stet's audio device controls, **Then** I can see the available microphones by recognizable name.
2. **Given** multiple microphones are available, **When** I select a specific microphone, **Then** Stet updates the active recording microphone to that device.
3. **Given** I previously selected an external microphone, **When** I switch back to the default built-in option, **Then** Stet stops treating that external device as my explicit preference.
4. **Given** the available microphones change while the app is open, **When** I reopen or refresh the device controls, **Then** the list reflects the microphones that are currently available.

---

### User Story 2 - Keep Recording Working When Devices Change (Priority: P1)

As a user, I want Stet to remember my preferred microphone and still start recording when that device is unavailable, so that hardware changes do not block dictation.

**Why this priority**: A remembered preference reduces repeated setup, and automatic fallback protects the primary dictation flow from device churn.

**Independent Test**: Select an external microphone, relaunch the app, verify the preference is retained, then disconnect that microphone and verify recording still starts with a fallback device.

**Acceptance Scenarios**:

1. **Given** I selected an external microphone earlier, **When** I relaunch Stet and that microphone is still available, **Then** Stet uses that microphone as my active selection.
2. **Given** I have not explicitly selected an external microphone, **When** Stet chooses a microphone automatically, **Then** it prefers the built-in microphone when that is available.
3. **Given** my explicitly selected external microphone is unavailable, **When** I start recording, **Then** Stet automatically falls back to another usable microphone and continues without requiring extra confirmation.
4. **Given** my explicitly selected external microphone is unavailable, **When** Stet falls back for recording, **Then** my saved preference remains intact so it can be used again when that device returns.

---

### User Story 3 - Switch Microphones Quickly From The Menu Bar (Priority: P2)

As a user, I want to switch microphones from the menu bar, so that I can change inputs without opening the full settings screen.

**Why this priority**: Quick switching improves day-to-day workflow, but it depends on the underlying selection behavior already working.

**Independent Test**: Open the menu bar device list, verify the current device is visibly selected, choose another device, and verify the selected state updates.

**Acceptance Scenarios**:

1. **Given** Stet is running, **When** I open the menu bar audio device list, **Then** I can see the available microphones and the default built-in option.
2. **Given** a microphone is currently active, **When** I view the menu bar list, **Then** I can identify which option is currently selected.
3. **Given** I choose a different microphone from the menu bar, **When** the selection is applied, **Then** Stet immediately updates the active microphone.

---

### User Story 4 - Test A Microphone In Settings (Priority: P2)

As a user, I want to test the currently selected microphone in Settings, so that I can confirm it is working before I start dictation.

**Why this priority**: Microphone testing reduces setup friction and gives users confidence that the selected input is usable.

**Independent Test**: Open Settings, start a test recording, verify live level feedback appears, stop the recording, and play it back successfully.

**Acceptance Scenarios**:

1. **Given** I am in Settings, **When** I open the audio device section, **Then** I can start and stop a microphone test recording.
2. **Given** a test recording is in progress, **When** audio is being captured, **Then** I can see live audio level feedback.
3. **Given** I completed a test recording, **When** I choose playback, **Then** I can hear the recorded sample.
4. **Given** I switch to a different microphone in Settings, **When** I run another test, **Then** I can validate that microphone separately.

---

### Edge Cases

- What happens when no usable microphones are currently available?
- What happens when the selected microphone is disconnected between selection time and recording start?
- How does the app behave when two microphones have similar or identical user-facing names?
- What happens when microphones are added or removed while Settings or the menu bar device list is open?
- What happens when the user has a remembered external preference, but the UI currently shows a fallback microphone because that device is unavailable?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST present the microphones currently available to Stet using recognizable names.
- **FR-002**: The system MUST allow the user to choose a specific external microphone as the active input device.
- **FR-003**: The system MUST allow the user to return to the default built-in input behavior.
- **FR-004**: The system MUST remember an explicitly selected external microphone across app relaunches.
- **FR-005**: When no explicit external microphone is selected, the system MUST prefer the built-in microphone when it is available.
- **FR-006**: If the explicitly selected microphone is unavailable at recording time, the system MUST automatically use another available microphone so recording can still proceed.
- **FR-007**: If fallback occurs because an explicitly selected microphone is unavailable, the system MUST preserve the user's saved preference for that microphone.
- **FR-008**: The system MUST refresh available microphone choices to reflect hardware connection changes.
- **FR-009**: The system MUST provide a menu bar surface for quickly switching the active microphone.
- **FR-010**: The menu bar surface MUST indicate which microphone is currently active.
- **FR-011**: The system MUST provide microphone test controls in Settings.
- **FR-012**: The Settings microphone test MUST provide live audio level feedback while recording.
- **FR-013**: The Settings microphone test MUST allow playback of the recorded sample.

### Key Entities *(include if feature involves data)*

- **Audio Input Device**: A microphone input Stet can display, select, and use for recording.
- **Device Preference**: The user's current choice between the default built-in route and an explicitly selected external microphone.
- **Microphone Test Session**: A short recording and playback flow used to validate that the currently selected microphone is functioning.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In manual validation, users can see and switch between the microphones currently available to Stet without restarting the app.
- **SC-002**: An explicitly selected external microphone remains selected after relaunch whenever that microphone is still available.
- **SC-003**: When an explicitly selected microphone is unavailable, recording can still be started using a fallback microphone without extra user action.
- **SC-004**: Users can complete a Settings microphone test that includes recording, live level feedback, and playback.
- **SC-005**: Users can identify and change the active microphone from the menu bar in a single menu interaction.

## Assumptions

- This specification is limited to macOS audio input device management in Stet.
- Users have already granted microphone permission to Stet when they attempt to record or run a microphone test.
- Onboarding may eventually reuse this feature's capabilities, but onboarding-specific microphone test behavior is not part of the currently completed implementation described here.
- Detailed device ranking heuristics, persistence mechanisms, and recording retry behavior are implementation concerns and are not specified here unless they affect user-visible behavior.
