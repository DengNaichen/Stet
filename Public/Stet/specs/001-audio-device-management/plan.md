# Implementation Plan: Audio Device Management

**Branch**: `001-audio-device-management` | **Date**: 2026-03-26 | **Spec**: [spec.md](./spec.md)  
**Input**: Existing feature behavior implemented in the current codebase, documented without code changes

## Summary

This plan documents the current design of Stet's macOS audio device management feature. The feature combines device enumeration, device preference resolution, recording fallback behavior, Settings-based device control, menu bar switching, and microphone testing in Settings.

The goal of this document is not to propose a new implementation. It is to explain how the existing implementation is structured today so that `spec.md`, `data-model.md`, and `contracts/` stay aligned with the code that currently ships in this branch.

## Technical Context

**Language/Version**: Swift with Swift Concurrency on macOS  
**Primary Dependencies**:
- CoreAudio for hardware device enumeration and change notifications
- AVFoundation for capture routing, recording, playback, and audio levels
- SwiftUI and Combine for Settings and menu bar state propagation

**Storage**:
- `UserDefaults` via `MacPreferences.preferredAudioInputDeviceUID` for remembered external-device preference

**Testing**:
- Swift Testing for device selection, resolver, device enumeration, and device change monitoring
- Manual validation for Settings UI, menu bar UI, and microphone test behavior

**Target Platform**: macOS  
**Project Type**: Native desktop application  
**Constraints**:
- Documentation must reflect the current implementation exactly
- No code changes are part of this documentation pass
- Product-facing docs should not over-promise incomplete onboarding behavior

## Constitution Check

This feature's documentation follows the current Constitution structure:

- `spec.md` is treated as a product specification focused on user-visible behavior.
- `data-model.md` is limited to the domain entities, state, and persistence concepts that matter to the feature.
- `contracts/` is limited to interfaces consumed across feature or module boundaries.
- `plan.md` is used as the feature's design document.
- `tasks.md` remains intentionally unwritten in this pass because the current work is documentation alignment rather than execution planning.

## Project Structure

### Documentation

```text
specs/001-audio-device-management/
├── spec.md
├── plan.md
├── data-model.md
└── contracts/
    ├── AudioDeviceSelectionManager.md
    ├── AudioDeviceChangeMonitor.md
    └── MicrophoneTestService.md
```

### Relevant Source Code

```text
StetMac/Core/Audio/Devices/
├── AudioHardwareDevice.swift
├── AudioInputDeviceManager.swift
├── AudioDeviceProviding.swift
├── AudioDeviceSelectionResolver.swift
├── AudioDeviceSelectionManager.swift
└── AudioDeviceChangeMonitor.swift

StetMac/Core/Audio/Capture/
├── MacCaptureAudioCaptureError.swift
├── MacCaptureAudioDevicePlanner.swift
└── MacCaptureAudioFileRecorder.swift

StetMac/Core/Speech/
└── MacAudioCaptureService.swift

StetMac/Features/MacShell/AudioDeviceManagement/
├── AudioInputDeviceSettingsSection.swift
└── AudioInputDeviceMenuSection.swift

StetMac/Features/MacShell/AudioSetting/
├── MacAudioSettingsView.swift
└── MacAudioSettingsViewModel.swift

StetMac/Features/Dictation/MicrophoneTest/
├── MicrophoneTestService.swift
├── DefaultMicrophoneTestService.swift
├── MicrophoneTestViewModel.swift
└── MicrophoneTestView.swift

StetMac/Features/Onboarding/Components/
└── OnboardingComponents.swift
```

### Relevant Tests

```text
StetMacTests/Core/Audio/Devices/
├── AudioInputDeviceManagerTests.swift
├── AudioDeviceSelectionResolverTests.swift
├── AudioDeviceSelectionManagerTests.swift
└── AudioDeviceChangeMonitorTests.swift

StetMacTests/Core/Audio/Capture/
└── MacCaptureAudioDevicePlannerTests.swift
```

## Design Overview

### 1. Device Enumeration And Representation

`AudioInputDeviceManager` is the CoreAudio-backed source of truth for available macOS input devices. It can:

- enumerate all input-capable devices
- return the current system default input device
- return the built-in input device when one is available
- return the current default output device for logging

Devices are represented as `AudioHardwareDevice` values with a stable `uid`, a user-visible `name`, and transport metadata used for routing decisions.

### 2. Selection State And Preference Resolution

`AudioDeviceSelectionManager` owns the feature's application-facing state. It is the interface consumed by Settings, the menu bar, and recording startup.

The manager delegates selection logic to `AudioDeviceSelectionResolver`, which resolves:

- the list of available devices
- the persisted preferred external device UID, if any
- the current system default input device

into:

- the current preference mode
- the active device used by the app
- a fallback indicator when an unavailable external preference forces the app back to a built-in route

The current implementation models "default built-in behavior" as the absence of a stored external UID rather than as a separately persisted strategy value.

### 3. Recording Integration And Fallback

`MacAudioCaptureService` asks `AudioDeviceSelectionManager` for the current recording device before starting macOS capture.

`MacCaptureAudioFileRecorder` then delegates candidate generation and capture-device resolution to `MacCaptureAudioDevicePlanner`. The planner currently supports:

- the selected device when one is actively chosen
- an AVCapture default-route fallback
- a built-in input fallback
- a system-default input fallback

The recorder retries startup across candidates and logs the path taken. This behavior is intentionally treated as implementation detail in `spec.md`, but it is central to the current design.

### 4. User-Facing Surfaces

The current implementation exposes the feature in two places:

- **Settings** via `AudioInputDeviceSettingsSection`
- **Menu Bar** via `AudioInputDeviceMenuSection`

Both surfaces consume `AudioDeviceSelectionManager` directly and refresh in response to `AudioDeviceChangeMonitor.devicesDidChangeNotification`.

The Settings surface exposes:

- a default built-in option
- explicit external device choices
- a "Current Device" display
- the microphone test UI

The menu bar surface exposes:

- a default built-in option
- explicit external device choices
- a checkmark for the currently active device

### 5. Microphone Test Flow

The microphone test feature is implemented in Settings using:

- `MicrophoneTestService`
- `DefaultMicrophoneTestService`
- `MicrophoneTestViewModel`
- `MicrophoneTestView`

The default service reuses `MacAudioCaptureService`, so the microphone test records with the same capture stack and current selection state used by dictation. The view model exposes recording, playback, and live level state to SwiftUI.

## Complexity Tracking

| Area | Why It Exists In The Current Design | Simpler Alternative Rejected By The Current Implementation |
|------|--------------------------------------|------------------------------------------------------------|
| Separate selection resolver | Keeps preference resolution deterministic and testable outside UI state | Embedding all resolution logic directly in the manager would make behavior harder to test and reason about |
| Recording-device cache | Allows synchronous access from non-main-actor recording code | Forcing the entire capture pipeline through async UI-bound access would increase coupling |
| Capture candidate fallback chain | Keeps dictation startup resilient when a preferred route is unavailable | A single-route startup path would fail more often when hardware state changes |

## Implementation Observations

The items below are observations about the current implementation. They are not requests for code changes in this documentation pass.

### 1. Onboarding Microphone Test Is Not Fully Implemented

The onboarding permissions step currently shows a microphone meter with a hard-coded `0.0` level and a `Start Recording` button whose action is still marked `TODO`. This means onboarding currently reuses the visual concept of microphone testing, but it does not yet implement the actual Settings microphone test workflow.

### 2. Preferred Device And Active Device Can Diverge

When a remembered external microphone becomes unavailable, the manager preserves the external preference but exposes the fallback route as the current active device. This is a reasonable resilience choice, but it means the current UI state is centered on what the app is using now, not on separately showing the unavailable remembered preference.

### 3. Microphone Test Has No Dedicated Automated Test Coverage Yet

The device-selection and device-monitoring logic has direct automated test coverage. The Settings microphone test flow does not currently appear to have dedicated automated tests in `StetTests`, so its behavior is presently documented based on implementation inspection rather than test coverage.
