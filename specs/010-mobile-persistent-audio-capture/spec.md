# Feature Specification: StetMobile Persistent Audio Capture

**Feature Branch**: `010-mobile-persistent-audio-capture`
**Created**: 2026-07-19
**Status**: Implemented
**Input**: Keep StetMobile ready for background keyboard dictation without taking the AirPods microphone from another device

## User Scenarios & Testing

### User Story 1 - Keep Dictation Ready Without Reclaiming AirPods (Priority: P1)

As a StetMobile user, I want background microphone readiness to prefer the iPhone microphone, so that AirPods can remain connected to and in use by my Mac or iPad.

**Acceptance Scenarios**:

1. **Given** StetMobile is prepared in the background, **When** AirPods move to another device, **Then** StetMobile does not enable a Bluetooth input route that pulls them back.
2. **Given** AirPods are in use by another device, **When** keyboard dictation starts, **Then** StetMobile records through the built-in microphone when iOS accepts that preference.
3. **Given** iOS does not accept the built-in input preference, **When** capture starts or a route changes, **Then** dictation continues on the system-selected input and logs a fallback.

### User Story 2 - Continue Dictation Across Route Changes (Priority: P1)

As a user, I want an in-progress dictation to survive audio route changes, so that connecting or disconnecting AirPods does not discard the session.

**Acceptance Scenarios**:

1. **Given** dictation is active, **When** the input route changes, **Then** the capture graph is rebuilt and the active frame consumer remains attached.
2. **Given** several equivalent route notifications arrive together, **When** recovery is already running, **Then** recovery work is coalesced rather than forming a notification loop.
3. **Given** recovery cannot restore the preferred input, **When** another system input remains usable, **Then** capture continues and records `systemFallback`.

### User Story 3 - Share One Warm Capture Resource Across Recognizers (Priority: P1)

As a user, I want SenseVoice and FunASR to share the same warm capture resource, so that changing recognition engines does not create competing audio sessions.

**Acceptance Scenarios**:

1. **Given** either recognizer is selected, **When** the app prepares audio, **Then** a single shared capture service owns `AVAudioSession`, `AVAudioEngine`, the tap, conversion, and route observation.
2. **Given** no dictation is active, **When** RemoteIO remains warm, **Then** no audio frames are delivered to either recognizer.
3. **Given** the user switches recognizers, **When** the previous coordinator shuts down, **Then** its consumer is removed before the new recognizer binds to the shared capture service.

### User Story 4 - Retain Explicit AirPods High-Quality Capture (Priority: P2)

As a developer, I want the existing AirPods HFP and iOS 26 high-quality recording configuration preserved as an explicit strategy, so that a future caller can opt into it without changing the current StetMobile policy.

**Acceptance Scenarios**:

1. **Given** `airPodsHighQuality` is constructed, **When** its session options are resolved, **Then** Bluetooth HFP is enabled and iOS 26 or later also enables high-quality recording.
2. **Given** the production StetMobile composition is created, **When** it constructs shared capture, **Then** it selects only `builtInPreferred`.

## Requirements

- **FR-001**: Shared capture MUST emit 16 kHz mono Float32 samples with a normalized level.
- **FR-002**: `prepare()` MUST keep the audio engine warm; `start()` and `stop()` MUST only open and close frame delivery.
- **FR-003**: Shared capture MUST allow no more than one active frame consumer.
- **FR-004**: `builtInPreferred` MUST use `.playAndRecord`, `.default`, and `.mixWithOthers` without Bluetooth input options.
- **FR-005**: After activation, `builtInPreferred` MUST request `.builtInMic` and verify `currentRoute`.
- **FR-006**: A rejected preference MUST resolve to `systemFallback` without preventing capture.
- **FR-007**: Real route changes MUST reapply policy and rebuild the tap/converter while preserving the active consumer.
- **FR-008**: Teardown MUST stop the engine, remove the tap, and deactivate with `.notifyOthersOnDeactivation`.
- **FR-009**: SenseVoice MUST only consume shared Float32 frames for VAD and recognition.
- **FR-010**: FunASR MUST only encode shared Float32 frames to PCM16, queue them, and upload them.
- **FR-011**: The macOS input-selection and recording behavior MUST remain unchanged.

## Success Criteria

- AirPods used by another device remain there for at least two minutes while StetMobile is warm in the background.
- Both SenseVoice and FunASR can dictate using the iPhone microphone while AirPods are busy elsewhere.
- Active dictation continues producing text through AirPods connection changes.
- Logs identify strategy, requested input, actual input, resolution, fallback, and recovery outcome.
- Automated tests cover strategy options, resolution, frame gating, recovery coalescing, teardown, FunASR encoding, and engine switching order.

## Assumptions

- No microphone settings or other UI are added.
- Background `audio` mode and the existing keyboard wake-up path remain enabled.
- `AVAudioSession.setPreferredInput` is a request, not a guaranteed physical-device binding.
- iOS exposes a logical microphone to `AVCaptureSession`; physical input remains controlled by audio routing, so capture is not migrated to `AVCaptureSession` for this feature.
- The current machine lacks the iOS 26.5 platform component; device validation requires a matching installed platform.
