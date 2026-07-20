# Data Model: Audio Device Management

## Overview

This document describes the domain data and state that drive the current macOS audio device management feature in Stet. It focuses on feature-level entities and relationships rather than framework-specific implementation details.

## Core Entities

### AudioHardwareDevice

Represents a single audio input device that Stet can discover, display, select, or use for recording.

**Key Attributes**:
- `id`: Session-scoped hardware identifier from CoreAudio
- `uid`: Stable identifier used to recognize the same device across launches
- `name`: User-visible device name
- `transportType`: Hardware transport classification used for routing decisions

**Derived Behavior**:
- A device may be treated as built-in based on transport type.
- A device may be ranked for automatic selection using transport-based priority rules.

**Invariants**:
- `uid` is expected to be non-empty when the device is surfaced to the feature.
- `name` is expected to be non-empty when the device is surfaced to the feature.
- A surfaced device must support audio input.

### DevicePreference

Represents the user's intended microphone preference.

**States**:
- `builtInDefault`: Use the feature's default built-in-first behavior
- `external(uid)`: Prefer a specific external device identified by stable UID

**Persistence**:
- Only the preferred external device UID is persisted.
- The built-in default state is represented by the absence of a stored external UID.

### DeviceSelectionState

Represents the resolved device state the app uses at runtime.

**Key Attributes**:
- `availableDevices`: Devices currently visible to the app
- `preference`: The user's remembered preference
- `activeDevice`: The device the app will currently use
- `isUsingFallbackBuiltIn`: Whether the app fell back from a remembered external preference to a built-in route

**Important Behavior**:
- `preference` and `activeDevice` can differ when an external preference is remembered but unavailable.
- The current UI is centered on `activeDevice`, not on separately displaying an unavailable preferred device.

### MicrophoneTestSession

Represents the short-lived test flow exposed in Settings.

**Key Attributes**:
- `isRecording`: Whether a test recording is currently being captured
- `isPlaying`: Whether the saved test clip is currently playing back
- `audioLevel`: The current live level value exposed to the UI while recording
- `hasRecording`: Whether a completed test recording is available for playback
- `recordingURL`: Temporary location of the saved test clip

**Lifecycle**:
- Starts idle
- Enters recording while capture is active
- Transitions to recorded when capture completes successfully
- Enters playing during playback
- Returns to idle or recorded when playback stops

## Relationships

- `AudioDeviceSelectionManager` resolves `DevicePreference` against the current list of `AudioHardwareDevice` values to produce `DeviceSelectionState`.
- `MacAudioCaptureService` consumes the current active device from the selection state when starting recording.
- `MicrophoneTestSession` depends on the same capture stack and current selection state used for dictation.

## State Transitions

### Device Preference Transitions

```text
builtInDefault -> external(uid)
external(uidA) -> external(uidB)
external(uid) -> builtInDefault
```

These transitions occur when the user changes the selected microphone in Settings or from the menu bar.

### Device Resolution Transitions

```text
preferred external available
  -> activeDevice = preferred external

preferred external unavailable
  -> activeDevice = built-in device when available
  -> otherwise activeDevice = system default or highest-ranked available route
  -> remembered preference remains external(uid)

no external preference
  -> activeDevice = built-in device when available
  -> otherwise activeDevice = system default or highest-ranked available route
```

### Microphone Test Session Transitions

```text
idle -> recording -> recorded -> playing -> recorded
idle -> recording -> idle            (failed or cancelled)
recorded -> playing -> recorded
```

## Persistence Model

Persisted data in the current implementation is intentionally small:

- `preferredAudioInputDeviceUID`
  - storage: `UserDefaults`
  - purpose: remember an explicitly selected external microphone
  - stable identifier: device `uid`

The following state is not persisted:

- current `availableDevices`
- current `activeDevice`
- current fallback state
- microphone test session state and recordings

## Invariants

- Only one active recording device is exposed at a time.
- A missing preferred external device does not erase the remembered external preference.
- A user action that selects the built-in default route clears the remembered external preference.
- The microphone test flow operates on the same selected recording route used by dictation.

## Out Of Scope For This Data Model

The following are part of implementation design rather than the feature data model:

- AVCapture candidate ordering and retry counts
- CoreAudio property-address mechanics
- exact logging format and diagnostics output
- internal locking and actor-isolation details
