# Contract: AudioDeviceSelectionManager

## Purpose

Defines the application-facing interface for audio device selection state. This manager is the primary contract consumed by Settings, the menu bar, and macOS recording startup.

## Consumers

- Settings UI
- Menu bar microphone menu
- macOS capture startup path

## Surface

```swift
@MainActor
final class AudioDeviceSelectionManager: ObservableObject {
    static let shared: AudioDeviceSelectionManager

    @Published private(set) var selectedDevice: AudioHardwareDevice?
    @Published private(set) var availableDevices: [AudioHardwareDevice]

    private(set) var preference: AudioDeviceSelectionResolver.Preference
    private(set) var activeDevice: AudioHardwareDevice?
    private(set) var isUsingFallbackBuiltIn: Bool

    init(provider: AudioDeviceProviding, defaults: UserDefaults = .standard)

    nonisolated func currentRecordingDevice() -> AudioHardwareDevice?
    func refreshDevices()
    func selectDevice(_ device: AudioHardwareDevice)
    func selectBuiltInDefault()
}
```

## Contract Guarantees

### Shared State

- `availableDevices` reflects the devices currently returned by the configured provider.
- `selectedDevice` reflects the device currently exposed to app consumers as active.
- `preference` preserves the remembered external-device intent even when the active device falls back.
- `activeDevice` is the device the app will currently use.
- `isUsingFallbackBuiltIn` is true only when an unavailable remembered external preference causes the active route to fall back to a built-in device.

### refreshDevices()

**Preconditions**:
- None

**Behavior**:
- Re-reads the available devices from the provider
- Re-resolves the active route against current hardware state and stored preference

**Postconditions**:
- Published state is updated to match the latest resolved selection state

### selectDevice(_:)

**Preconditions**:
- Caller provides a device from the current available set

**Behavior**:
- If the provided device is built-in, the manager behaves the same as `selectBuiltInDefault()`
- If the provided device is external, its UID becomes the remembered preferred input device

**Postconditions**:
- The active route is re-resolved immediately
- The remembered external preference is persisted

### selectBuiltInDefault()

**Preconditions**:
- None

**Behavior**:
- Clears any remembered external-device preference
- Re-resolves the active route using built-in-default behavior

**Postconditions**:
- No external UID remains persisted

### currentRecordingDevice()

**Purpose**:
- Provides a synchronous snapshot for non-main-actor consumers such as capture startup

**Behavior**:
- Returns the manager's most recent resolved active device snapshot
- Does not require the caller to enter the main actor

## Error Handling

- This contract does not throw errors.
- Failures in underlying enumeration or default-device lookup degrade into empty device lists or nil active-device results rather than thrown failures at this layer.

## Threading

- The manager's mutable UI-facing state is main-actor isolated.
- `currentRecordingDevice()` is intentionally nonisolated and returns a cached snapshot for synchronous consumers.

## Notes

- The current implementation uses the absence of a stored external UID to represent built-in-default behavior.
- In fallback scenarios, `preference` may still represent an unavailable external device while `selectedDevice` and `activeDevice` point to the fallback route.
