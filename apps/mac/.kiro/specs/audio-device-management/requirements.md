# Requirements Document: Audio Device Management

## Overview

This document specifies the requirements for the audio-device-management feature. This feature enables users to see and select from all available microphones on their system.

---

## User Story 1: Discover Available Microphones

**As a user**, I want to see all the microphones available on my computer, so that I can choose which one to use for dictation.

### Acceptance Criteria

1. When I open the device selection menu, I can see a list of all connected microphones
2. Each microphone is displayed with a clear, recognizable name (e.g., "Built-in Microphone", "USB Headset", "AirPods")
3. If I plug in a new microphone, it appears in the list
4. If I unplug a microphone, it disappears from the list
5. The list always shows at least one microphone (the system default)

---

## User Story 2: Identify Different Microphones

**As a user**, I want to easily distinguish between different microphones, so that I can select the right one for my needs.

### Acceptance Criteria

1. Each microphone shows its type or connection method (e.g., "Built-in", "USB", "Bluetooth")
2. The microphone names are clear and descriptive enough to identify them
3. If I have multiple similar microphones, I can tell them apart by their names

---

## User Story 3: Remember My Preferred Microphone

**As a user**, I want the system to remember which microphone I prefer, so that it automatically uses my preferred microphone for dictation without me having to select it every time.

### Acceptance Criteria

1. When I select an external microphone for dictation, the system remembers my choice
2. The next time I use dictation, it uses my preferred external microphone by default
3. If I select the built-in microphone, the system clears any external device preference and uses the built-in default strategy
4. If my preferred external microphone is not available (e.g., unplugged), the system falls back to the built-in microphone (if available) or the system default
5. I can change my preferred microphone at any time
6. The system indicates when it's using a fallback device (via `isUsingFallbackBuiltIn` flag)

---

## User Story 4: Prioritize Audio Quality Over System Default

**As a user**, I want Stet to use the highest quality microphone available by default, even if the system has selected a lower-quality device (like AirPods), so that my dictation quality is not compromised.

### Acceptance Criteria

1. When I'm using AirPods or other Bluetooth devices as the system default, Stet automatically uses the built-in MacBook microphone for recording instead
2. The system intelligently avoids low-quality audio channels (like Bluetooth's "dual-channel" mode) that degrade input quality
3. By default, Stet prioritizes audio quality and automatically selects the built-in microphone when available
4. The quality prioritization happens automatically without requiring user configuration
5. The built-in microphone has the highest automatic selection priority (500), followed by external professional devices (400), and Bluetooth devices have lower priority (100)

---

## User Story 5: Manually Select a Specific Microphone

**As a user**, I want to be able to manually select any microphone I want to use, so that I have full control over which device Stet uses for recording.

### Acceptance Criteria

1. I can access a settings or menu option to manually select a microphone
2. When I manually select an external microphone, Stet uses that microphone for the next recording and persists my preference
3. When I manually select the built-in microphone, Stet clears any external device preference and uses the built-in default strategy
4. My manual selection overrides the default quality-prioritization behavior
5. I can change my manual selection at any time before or after recording
6. If my manually selected external device becomes unavailable, the system falls back to the built-in microphone but preserves my preference

---

## User Story 6: Quick Device Switching from Menu Bar

**As a user**, I want to quickly switch between microphones from the Menu Bar, so that I can change devices without opening settings.

### Acceptance Criteria

1. There is a microphone icon or menu in the Menu Bar
2. When I click it, a dropdown menu shows all available microphones
3. I can see which microphone is currently selected
4. I can click on any microphone to switch to it immediately
5. The menu closes after I make a selection

---

## User Story 7: Test Microphone in Settings

**As a user**, I want to test my microphone in the Settings, so that I can verify it's working properly before using it for dictation.

### Acceptance Criteria

1. There is a "Test Microphone" option in the Settings
2. When I click it, I can record a short audio sample
3. I can hear a playback of what I just recorded
4. I can see real-time audio level feedback while recording
5. I can test different microphones by switching devices and testing again

---

## User Story 8: Test Microphone During Onboarding

**As a new user**, I want to test my microphone during the Onboarding process, so that I can verify everything is working before I start using Stet.

### Acceptance Criteria

1. The Onboarding flow includes a microphone test step
2. I can record a short audio sample and hear it played back
3. I can see real-time audio level feedback while recording
4. If the test is successful, I can proceed to the next step
5. If there's an issue, I get helpful guidance on how to fix it

---

## Technical Story 9: Audio Capture Pipeline Resilience

**As a system**, I want to implement a robust audio capture pipeline with multiple fallback strategies, so that recording can succeed even when the preferred device is unavailable.

### Acceptance Criteria

1. When starting a recording, the system generates a list of candidate devices in priority order
2. The system attempts to use each candidate device in sequence until one succeeds
3. If a device fails to start, the system automatically tries the next candidate without user intervention
4. The system implements retry logic for transient failures (up to 4 attempts per device)
5. The system logs detailed information about device selection and fallback attempts for debugging
6. If all candidates fail, the system provides a clear error message

### Candidate Device Priority Order

1. **Selected Device**: User's manually selected device (if any)
2. **No Explicit Device Fallback**: System default device via AVCapture automatic selection
3. **Built-in Fallback**: Internal microphone (most reliable)
4. **System Default Fallback**: CoreAudio default input device

### Device Resolution Strategy

When resolving a candidate device to an AVCaptureDevice:

1. If no specific device is requested, use `AVCaptureDevice.default(for: .audio)`
2. Otherwise, match by exact UID (most reliable)
3. If UID doesn't match, try exact name match
4. For built-in devices, try fuzzy name match (contains "microphone" or "macbook")
5. If no match found, throw error and try next candidate

### Retry and Timing

- Each device candidate gets up to 4 startup attempts
- Retry delay: 0.15 seconds between attempts
- Candidate switch delay: 0.1 seconds between different candidates
- Total maximum startup time: ~2 seconds (4 candidates × 4 retries × 0.15s)
