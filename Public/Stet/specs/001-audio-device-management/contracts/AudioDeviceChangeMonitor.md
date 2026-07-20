# Contract: AudioDeviceChangeMonitor

## Purpose

Defines the notification-based interface for observing macOS audio hardware changes.

## Consumers

- Settings audio device section
- Menu bar microphone menu
- Any feature that needs to refresh visible microphone choices when hardware changes

## Surface

```swift
final class AudioDeviceChangeMonitor {
    static let shared: AudioDeviceChangeMonitor
    static let devicesDidChangeNotification: Notification.Name

    init()

    func startMonitoring()
    func stopMonitoring()
}
```

## Contract Guarantees

### devicesDidChangeNotification

- Notification name: `AudioDevicesDidChange`
- Semantics: indicates that the CoreAudio device list changed and consumers should refresh their visible device state

### startMonitoring()

**Preconditions**:
- None

**Behavior**:
- Begins monitoring CoreAudio device-list changes
- Supports repeated calls by reference-counting monitor clients

**Postconditions**:
- Consumers that observe `devicesDidChangeNotification` can receive future change notifications

### stopMonitoring()

**Preconditions**:
- None

**Behavior**:
- Decrements monitoring usage
- Stops the underlying CoreAudio listener when no clients remain

**Postconditions**:
- Calling `stopMonitoring()` without a matching active monitor client is harmless

## Error Handling

- Monitoring failures are logged internally.
- This contract does not throw errors to its consumers.

## Notes

- This interface is intentionally narrow: it reports that device state changed, not how it changed.
- Consumers are expected to call back into their selection state source and refresh devices after notification delivery.
