# Contract: AppBranchMonitor

## Purpose

`AppBranchMonitor` is the public runtime interface used by other app modules to read the current frontmost app, observe app switches, and configure exclusion behavior.

## Public Surface

### `AppBranchMonitor`

```swift
public nonisolated final class AppBranchMonitor: @unchecked Sendable
public nonisolated static let shared: AppBranchMonitor

public nonisolated var currentApp: AppInfo? { get }
public nonisolated var isMonitoring: Bool { get }
public nonisolated var excludedBundleID: String? { get set }

public nonisolated func startMonitoring()
public nonisolated func stopMonitoring()
public nonisolated func addObserver(_ callback: @escaping AppChangeCallback) -> UUID
public nonisolated func removeObserver(_ id: UUID)
public nonisolated func setExcludedBundleID(_ bundleID: String?)
```

### `AppInfo`

```swift
public nonisolated struct AppInfo: Equatable, @unchecked Sendable
public let bundleIdentifier: String
public let localizedName: String
public let processIdentifier: pid_t
public let isOwnHostApplication: Bool
public let runningApplication: NSRunningApplication?
```

### `AppChangeCallback`

```swift
public typealias AppChangeCallback = (AppInfo?) -> Void
```

## Behavior

- `currentApp` returns the latest resolved foreground app snapshot or `nil` when no usable app is available.
- `currentApp` is synchronous and does not require a caller to await a polling loop.
- `startMonitoring()` begins listening for app activation changes and is safe to call repeatedly.
- `stopMonitoring()` stops listening and is safe to call repeatedly.
- `addObserver(_:)` registers a callback and returns a UUID that can be used for removal.
- `removeObserver(_:)` is idempotent; removing an unknown UUID has no effect.
- `setExcludedBundleID(_:)` updates the runtime exclusion rule used when resolving `currentApp`.
- Observer callbacks may receive `nil` when the current app cannot be resolved or is excluded without fallback.
- Observer delivery is asynchronous and should not be assumed to happen on the caller's current thread.

## Input / Output Expectations

- **Input**: `UUID` values identify observer registrations, and optional bundle identifiers define exclusion rules.
- **Output**: `currentApp` returns an `AppInfo` snapshot when a valid frontmost app exists; otherwise it returns `nil`.
- **Output**: `addObserver(_:)` returns a stable `UUID`.
- **Output**: `AppInfo.runningApplication` may be `nil` if the live app reference is unavailable or the snapshot was built for testing.

## Error Handling

- The API does not throw.
- Invalid observer removals are ignored.
- Missing frontmost-app data is treated as an empty/absent result rather than as a crash.
- Excluded-app resolution falls back to the previous non-excluded app when available; otherwise it returns `nil`.

## Usage Example

```swift
let monitor = AppBranchMonitor.shared
monitor.setExcludedBundleID(Bundle.main.bundleIdentifier)

let observerID = monitor.addObserver { appInfo in
    // react to foreground app changes
}

monitor.startMonitoring()
let current = monitor.currentApp

// later
monitor.removeObserver(observerID)
monitor.stopMonitoring()
```

## Notes

- `AppBranchWorkspaceObserving` is intentionally not part of this contract; it is an internal test seam.
- `AppAudience` is also intentionally omitted because it is an internal derived value used by downstream prompt routing rather than a public contract surface.
- `AppChangeObserver` is intentionally omitted because consumers interact with observer registrations through `UUID` handles rather than the underlying registration record.
