# Design Document: app-branch

## Overview

The **app-branch** feature is a standalone macOS module that provides real-time detection of the currently active/foreground application using NSWorkspace APIs. The module operates independently from the main application thread, allowing other components or external systems to query the current frontmost application without direct coupling.

## Architecture

### High-Level Design

The module follows a simple observer pattern architecture with the following components:

```
┌─────────────────────────────────────────────────────────────┐
│                      AppBranchMonitor                        │
├─────────────────────────────────────────────────────────────┤
│  - shared: AppBranchMonitor                                  │
│  - currentApp: AppInfo?                                      │
│  - isMonitoring: Bool                                        │
│  - excludedBundleID: String?                                 │
│  - state: AppBranchMonitorState (private)                    │
│  - workspace: AppBranchWorkspaceObserving                    │
│  - callbackQueue: DispatchQueue                              │
│  - stateLock: NSRecursiveLock                                │
├─────────────────────────────────────────────────────────────┤
│  + startMonitoring()                                         │
│  + stopMonitoring()                                          │
│  + addObserver(_:) -> UUID                                   │
│  + removeObserver(_:)                                        │
│  + setExcludedBundleID(_:)                                   │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│            AppBranchWorkspaceObserving Protocol              │
├─────────────────────────────────────────────────────────────┤
│  - frontmostApplication: Snapshot?                           │
│  + observeFrontmostApplicationChanges(_:) -> Token           │
│  + removeObservation(_:)                                     │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                  LiveAppBranchWorkspace                      │
│              (NSWorkspace wrapper)                           │
├─────────────────────────────────────────────────────────────┤
│  - NSWorkspace.didActivateApplicationNotification           │
│  - NSWorkspace.shared.frontmostApplication                  │
└─────────────────────────────────────────────────────────────┘
```

### Implementation Details

**State Management:**
- All mutable state is encapsulated in `AppBranchMonitorState` struct
- State access is protected by `NSRecursiveLock` for thread safety
- `currentApp` is computed on-demand, not cached

**Notification Flow:**
1. Workspace detects app activation
2. Calls handler registered via `observeFrontmostApplicationChanges`
3. Handler schedules refresh on `callbackQueue`
4. `refreshAndNotifyObservers` queries workspace and notifies all observers

**Exclusion Logic:**
- When `excludedBundleID` is set and matches frontmost app
- Returns `previousApp` if available and different from excluded app
- Otherwise returns nil
- Tracks `previousApp` in state for fallback

### Design Decisions

1. **Observer Pattern**: Chosen over delegate pattern to support multiple concurrent observers
2. **Background Queue**: All notification handling runs on a dedicated callback queue to avoid blocking the main thread
3. **UUID-based Observer IDs**: Provides thread-safe observer management without complex locking
4. **Optional Exclusion**: Self-app exclusion is opt-in via configuration
5. **Workspace Abstraction**: `AppBranchWorkspaceObserving` protocol allows dependency injection for testing
6. **Lock-based Thread Safety**: Uses `NSRecursiveLock` for state synchronization instead of serial queue
7. **Computed Current App**: `currentApp` is computed on-demand from workspace snapshot, not cached
8. **App Audience Classification**: Automatic detection of AI vs human-targeted apps via `AppAudience`

## Components and Interfaces

### File Structure

```
apps/mac/Stet/Core/AppBranch/
├── AppBranchMonitor.swift       # Main monitor class
├── AppInfo.swift                # App info value type & observer types
├── AppBranchWorkspace.swift     # Workspace abstraction layer
└── AppAudience.swift            # App audience classification

apps/mac/StetTests/Core/
└── AppBranchTests.swift         # Test suite
```

### AppBranchMonitor

The main class that provides foreground application monitoring.

```swift
public final class AppBranchMonitor {
    public static let shared: AppBranchMonitor
    
    public var currentApp: AppInfo? { ... }
    public var isMonitoring: Bool { ... }
    public var excludedBundleID: String? { get set }
    
    init(
        workspace: any AppBranchWorkspaceObserving = LiveAppBranchWorkspace(),
        callbackQueue: DispatchQueue = ...
    )
    
    public func startMonitoring()
    public func stopMonitoring()
    public func addObserver(_ callback: @escaping AppChangeCallback) -> UUID
    public func removeObserver(_ id: UUID)
    public func setExcludedBundleID(_ bundleID: String?)
}
```

### AppInfo

A value type containing information about the foreground application.

```swift
public struct AppInfo: Equatable {
    public let bundleIdentifier: String
    public let localizedName: String
    public let processIdentifier: pid_t
    public let isOwnHostApplication: Bool
    public let runningApplication: NSRunningApplication?
    
    var audience: AppAudience { ... }
}
```

### Observer Types

```swift
public typealias AppChangeCallback = (AppInfo?) -> Void

public struct AppChangeObserver {
    public let id: UUID
    public let callback: AppChangeCallback
    public let createdAt: Date
}
```

### Workspace Abstraction

```swift
protocol AppBranchWorkspaceObserving {
    var frontmostApplication: AppBranchWorkspaceApplicationSnapshot? { get }
    func observeFrontmostApplicationChanges(_ handler: @escaping () -> Void) -> AppBranchWorkspaceObservationToken
    func removeObservation(_ token: AppBranchWorkspaceObservationToken)
}

final class LiveAppBranchWorkspace: AppBranchWorkspaceObserving {
    // Wraps NSWorkspace for production use
}

struct AppBranchWorkspaceApplicationSnapshot {
    let bundleIdentifier: String?
    let localizedName: String?
    let processIdentifier: pid_t
    let runningApplication: NSRunningApplication?
}
```

### App Audience Classification

```swift
enum AppAudience: String, Codable, Sendable {
    case human
    case ai
}

enum AppAudienceResolver {
    static func resolve(bundleIdentifier: String, localizedName: String) -> AppAudience
    // Classifies apps as .ai or .human based on name patterns
}
```

## Data Models

### AppInfo

| Field | Type | Description |
|-------|------|-------------|
| bundleIdentifier | String | Unique identifier (e.g., "com.apple.Safari") |
| localizedName | String | User-visible app name |
| processIdentifier | pid_t | Process ID |
| isOwnHostApplication | Bool | Whether this is the host app |
| runningApplication | NSRunningApplication? | Full NSRunningApplication reference (optional) |
| audience | AppAudience | Computed property: .human or .ai based on app classification |

### Configuration

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| excludedBundleID | String? | nil | Bundle ID to exclude from detection |
| workspace | AppBranchWorkspaceObserving | LiveAppBranchWorkspace() | Workspace abstraction for testing |
| callbackQueue | DispatchQueue | Background queue | Queue for observer callbacks |

## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions of a system-essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees.*

### Property 1: Current App Retrieval

*For any* AppBranchMonitor instance, when querying currentApp after starting monitoring, the returned AppInfo should contain a valid bundle identifier and localized name

**Validates: Requirements 1.1, 1.3, 1.4**

### Property 2: Observer Notification

*For any* AppBranchMonitor with registered observers, when the foreground application changes, all registered observers SHALL be invoked with the new AppInfo

**Validates: Requirements 1.2, 5.3, 5.4**

### Property 3: Bundle ID Availability

*For any* AppInfo returned by the monitor, the bundleIdentifier field SHALL be non-empty and valid

**Validates: Requirements 1.3**

### Property 4: Localized Name Availability

*For any* AppInfo returned by the monitor, the localizedName field SHALL be non-empty

**Validates: Requirements 1.4**

### Property 5: PID Retrieval

*For any* AppInfo, the processIdentifier SHALL match the actual PID of the NSRunningApplication

**Validates: Requirements 4.2**

### Property 6: Host App Detection

*For any* AppInfo, the isOwnHostApplication field SHALL be true when the app's bundle identifier matches Bundle.main.bundleIdentifier

**Validates: Requirements 4.3**

### Property 7: Observer Registration

*For any* AppBranchMonitor, adding an observer SHALL return a unique UUID that can be used to remove that observer

**Validates: Requirements 5.1**

### Property 8: Observer Unregistration

*For any* AppBranchMonitor with registered observers, after removing an observer by UUID, that observer SHALL NOT receive future notifications

**Validates: Requirements 5.2**

### Property 9: Monitoring State

*For any* AppBranchMonitor, after calling startMonitoring, isMonitoring SHALL be true, and after calling stopMonitoring, isMonitoring SHALL be false

**Validates: Requirements 7.2, 7.3**

### Property 10: Exclusion Behavior

*For any* AppBranchMonitor with an excludedBundleID set, when the excluded app is in the foreground, currentApp SHALL return the previously active application or nil

**Validates: Requirements 6.1, 6.2**

### Property 11: Thread Safety

*For any* AppBranchMonitor, calling addObserver, removeObserver, and receiving callbacks from multiple threads concurrently SHALL not cause race conditions or crashes

**Validates: Requirements 3.3**

### Property 12: Continuous Monitoring

*For any* AppBranchMonitor that is monitoring, multiple app switches SHALL all trigger observer callbacks without requiring manual polling

**Validates: Requirements 2.2, 2.3**

## Error Handling

### Error Cases

1. **No Frontmost Application**: When no application is active (rare), return nil gracefully
2. **Observer Not Found**: When removing an invalid UUID, silently ignore (idempotent operation)
3. **Notification Failure**: If NSWorkspace notification subscription fails, log error and set isMonitoring to false

### Thread Safety

- All state management uses `NSRecursiveLock` for synchronization
- Observer callbacks are dispatched to `callbackQueue` to avoid blocking callers
- AppInfo is a value type, ensuring safe passage between threads
- Workspace abstraction allows deterministic testing without race conditions

## Testing Strategy

### Dual Testing Approach

**Unit Tests** (specific examples and edge cases):
- Test start/stop monitoring state transitions
- Test observer add/remove operations
- Test exclusion configuration
- Test nil handling when no app is frontmost
- Test error handling scenarios

**Property Tests** (universal properties across all inputs):
- Test that all returned AppInfo has valid bundle identifiers
- Test that all observers receive notifications
- Test thread safety with concurrent access
- Test that monitoring continues without polling

### Testing Framework

- Framework: Swift Testing (native Swift testing framework)
- Test isolation: Uses dependency injection with fake workspace
- Iterations: Comprehensive coverage of edge cases
- Test Tags: `@Suite("AppBranch", .tags(.appBranch))`

### Test Categories

1. **Core Functionality Tests**: Verify basic app detection works
2. **Observer Tests**: Verify observer pattern implementation
3. **Thread Safety Tests**: Verify concurrent access is safe
4. **Integration Tests**: Verify workspace notification integration via protocol
5. **Edge Case Tests**: Handle nil app, rapid app switches
6. **Error Handling Tests**: Verify graceful error handling and logging

### Testability Features

- **Workspace Abstraction**: `AppBranchWorkspaceObserving` protocol allows fake workspace injection
- **Dependency Injection**: Monitor accepts workspace and queue parameters for testing
- **Deterministic Testing**: Fake workspace provides controlled app snapshots
- **No NSWorkspace Dependency**: Tests don't rely on actual system state

### Compatibility Notes

- Module supports macOS 12.0+
- Compatible with both SwiftUI and AppKit applications
- No main thread blocking during normal operation