# Feature Specification: Audio Capture Pipeline

**Feature Branch**: `003-audio-capture-pipeline`  
**Created**: 2026-03-27  
**Status**: Draft  
**Input**: User description: "Audio capture pipeline for dictation and microphone testing"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Start Recording for Dictation (Priority: P1)

As a user, I want dictation to start recording audio after permission is granted, so that my speech can be captured for transcription.

**Why this priority**: Recording start is the primary function of the capture pipeline.

**Independent Test**: Can be tested by starting a dictation session and verifying that capture begins only after microphone permission resolves successfully.

**Acceptance Scenarios**:

1. **Given** microphone permission is granted, **When** recording starts, **Then** audio capture begins successfully.
2. **Given** microphone permission is denied, **When** recording starts, **Then** capture fails with a permission error and does not create a recording file.
3. **Given** recording is already active, **When** start is requested again, **Then** the system rejects the second start request.

### User Story 2 - Stream Live Audio Levels (Priority: P2)

As a user, I want to see live audio level feedback while recording, so that I know the microphone is picking up sound.

**Why this priority**: Live levels are an important feedback loop for dictation and microphone testing, but they depend on capture already being active.

**Independent Test**: Can be tested by subscribing to the audio level stream during capture and observing changing values while speaking.

**Acceptance Scenarios**:

1. **Given** recording is active, **When** audio is captured, **Then** a normalized audio level stream produces values for the UI.
2. **Given** the input is silent, **When** levels are emitted, **Then** the stream still provides a visible non-zero floor value.
3. **Given** recording stops or is canceled, **When** the UI continues listening, **Then** the stream drops back to silence for the inactive state.

### User Story 3 - Write Captured Audio to a Transcribable File (Priority: P3)

As a user, I want captured audio to be written to a temporary file in the required transcription format, so that downstream transcription can consume it.

**Why this priority**: The capture pipeline must produce a usable file for transcription; otherwise recording has no value.

**Independent Test**: Can be tested by recording audio, stopping capture, and verifying that the returned file exists and can be read as a valid recording.

**Acceptance Scenarios**:

1. **Given** recording completes with captured audio, **When** the session stops, **Then** the system returns a file URL and duration.
2. **Given** the recording target is the macOS transcription path, **When** audio is written, **Then** the file is produced as 16 kHz mono linear PCM WAV.
3. **Given** capture stops without useful audio, **When** the file is validated, **Then** the system discards the file and reports an empty-recording failure.

### User Story 4 - Stop or Cancel Recording Cleanly (Priority: P4)

As a user, I want to stop or cancel capture cleanly, so that the recording lifecycle ends without leaving stale state behind.

**Why this priority**: Stop and cancel are required to close the capture loop and release resources safely.

**Independent Test**: Can be tested by starting a recording, stopping it, and canceling it from the same capture service.

**Acceptance Scenarios**:

1. **Given** capture is active, **When** stop is requested, **Then** the file is finalized and the session ends.
2. **Given** capture is active, **When** cancel is requested, **Then** the temporary recording file is discarded.
3. **Given** capture is inactive, **When** stop or cancel is requested, **Then** the system rejects the invalid lifecycle transition or no-ops according to the documented capture behavior.

### User Story 5 - Recover from Device and Session Failures (Priority: P5)

As a user, I want recording to recover from temporary microphone or session failures, so that a usable input device can still be selected when possible.

**Why this priority**: Capture failures should degrade gracefully instead of stopping the feature entirely.

**Independent Test**: Can be tested by simulating unavailable input devices and confirming that the capture service falls back or fails with a clear error.

**Acceptance Scenarios**:

1. **Given** the preferred device is unavailable, **When** recording starts, **Then** the system attempts supported fallback device candidates.
2. **Given** no capture device can be resolved, **When** recording starts, **Then** the system reports a start failure.
3. **Given** the capture session cannot start successfully, **When** recovery is attempted, **Then** the system either starts capture on a supported path or fails with a clear error.

### User Story 6 - Activate the Recording Window (Priority: P6)

As a user, I want the capture pipeline to buffer audio until the recording window is activated, so that pre-activation audio is preserved when the session becomes ready.

**Why this priority**: Window activation is needed for dictation startup behavior and early audio preservation.

**Independent Test**: Can be tested by buffering audio before activation and verifying that the buffered audio is written once the window is activated.

**Acceptance Scenarios**:

1. **Given** capture has started but the recording window is not yet active, **When** audio arrives, **Then** the pipeline buffers audio instead of writing it immediately.
2. **Given** buffered audio exists, **When** the recording window is activated, **Then** the buffered audio is written to the file.
3. **Given** buffering exceeds the allowed pending window, **When** new audio arrives, **Then** older buffered audio is discarded first.

### User Story 7 - Support Microphone Testing Consumers (Priority: P7)

As a user, I want microphone testing screens to reuse the same capture pipeline, so that they reflect the same capture behavior as dictation.

**Why this priority**: The pipeline is shared infrastructure and should support microphone testing without diverging behavior.

**Independent Test**: Can be tested by starting microphone test capture through the shared service and observing the same audio level and file behavior as dictation capture.

**Acceptance Scenarios**:

1. **Given** a microphone test consumer starts recording, **When** capture begins, **Then** it uses the same shared audio capture service.
2. **Given** a microphone test consumer requests levels, **When** capture is active, **Then** it receives the same normalized audio level stream.

### Edge Cases

- What happens when permission is denied after the user initiates recording?
- What happens when the selected device disappears before capture starts?
- What happens when a recording produces no meaningful audio?
- What happens when the capture session starts but the recording window is never activated?
- What happens when a consumer subscribes to the audio level stream before capture starts?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST request microphone permission before starting capture.
- **FR-002**: The system MUST refuse to start a new recording while another recording is already active.
- **FR-003**: The system MUST provide a normalized audio level stream during active capture.
- **FR-004**: The system MUST write captured audio to a temporary file that downstream transcription can consume.
- **FR-005**: The macOS capture path MUST produce 16 kHz mono linear PCM WAV output.
- **FR-006**: The system MUST support canceling an active recording and removing the temporary file.
- **FR-007**: The system MUST reject recordings that do not contain meaningful audio.
- **FR-008**: The system MUST support a recording-window activation step that buffers audio until activation occurs.
- **FR-009**: The system MUST attempt supported fallback input devices when the preferred input device cannot be used.
- **FR-011**: The system MUST expose a capture lifecycle suitable for dictation and microphone test consumers.

### Key Entities *(include if feature involves data)*

- **Capture Session**: One active recording lifecycle, including permission state, input selection, capture start, activation, stop, and cancel.
- **Recording Outcome**: The result returned when capture stops, including the file URL, duration, frame count, and whether meaningful audio was written.
- **Audio Level Reading**: A normalized scalar used by the UI to render live microphone feedback.
- **Pending Audio Window**: Buffered audio held before the recording window is activated.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A successful recording session returns a readable temporary audio file and duration.
- **SC-002**: Live audio levels are observable while capture is active.
- **SC-003**: Empty or insignificant recordings are rejected instead of being sent downstream.
- **SC-004**: The macOS capture path produces audio compatible with transcription without additional format conversion in the consumer.
- **SC-005**: The capture pipeline handles temporary device failures by either recovering with a supported fallback or failing with a clear error.

## Assumptions

- The feature is consumed by dictation and microphone test flows, but it does not own those UI flows.
- The macOS implementation is the primary reference for current behavior.
- Temporary recording files are ephemeral and are not intended to be long-lived user data.
- Device selection itself is owned by the audio device management feature, not this feature.
