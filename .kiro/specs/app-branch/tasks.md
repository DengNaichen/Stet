# Implementation Plan: app-branch

## Overview

This implementation creates a standalone macOS module for real-time foreground application detection using NSWorkspace APIs. The module follows the observer pattern for app change notifications and runs on a background queue to avoid blocking the main thread.

## Tasks

- [x] 1. Set up project structure and core types
  - [x] 1.1 Create AppInfo struct with all required properties
    - Define bundleIdentifier, localizedName, processIdentifier, isOwnHostApplication, runningApplication (optional)
    - Add computed audience property for app classification
    - Implement Equatable conformance
    - _Requirements: 1.3, 1.4, 4.1, 4.2, 4.3, 4.4_

  - [x] 1.2 Define observer types and callbacks
    - Create AppChangeCallback typealias
    - Create AppChangeObserver struct with id, callback, createdAt
    - _Requirements: 5.1, 5.3_

  - [x] 1.3 Create workspace abstraction layer
    - Define AppBranchWorkspaceObserving protocol
    - Create AppBranchWorkspaceApplicationSnapshot struct
    - Implement LiveAppBranchWorkspace wrapping NSWorkspace
    - Create AppBranchWorkspaceObservationToken for observation management
    - _Requirements: 3.1, testability_

  - [x] 1.4 Create app audience classification system
    - Define AppAudience enum (.human, .ai)
    - Implement AppAudienceResolver with AI app detection
    - _Requirements: 4.4_

  - [x] 1.5 Set up testing framework configuration
    - Configure Swift Testing framework
    - Add test tags for Feature: app-branch
    - _Requirements: Testing non-functional requirement_

- [x] 2. Implement AppBranchMonitor core class
  - [x] 2.1 Create AppBranchMonitor class with shared instance and dependency injection
    - Define static shared property
    - Add injectable workspace and callbackQueue parameters
    - Add currentApp (computed), isMonitoring, excludedBundleID properties
    - Create private AppBranchMonitorState struct
    - Add stateLock (NSRecursiveLock) for thread safety
    - _Requirements: 7.1, 7.2, 7.3, 3.1_

  - [x] 2.2 Implement startMonitoring method
    - Subscribe to workspace frontmost app changes via protocol
    - Set isMonitoring to true
    - Schedule initial workspace refresh on callbackQueue
    - _Requirements: 2.1, 2.2, 2.3, 7.2_

  - [x] 2.3 Implement stopMonitoring method
    - Remove workspace observation via protocol
    - Set isMonitoring to false
    - _Requirements: 7.3_

  - [x] 2.4 Implement currentApp property getter
    - Query workspace.frontmostApplication snapshot
    - Convert to AppInfo via resolveCurrentApp helper
    - Apply exclusion logic
    - Handle nil case gracefully with logging
    - _Requirements: 1.1, 1.3, 1.4, 4.1, 4.2_

  - [x] 2.5 Write unit tests for AppBranchMonitor core
    - Test startMonitoring sets isMonitoring to true
    - Test stopMonitoring sets isMonitoring to false
    - Test currentApp returns valid AppInfo
    - _Requirements: 7.2, 7.3_

  - [ ]* 2.6 Write property test for monitoring state
    - **Property 9: Monitoring State**
    - **Validates: Requirements 7.2, 7.3**

- [x] 3. Implement observer pattern
  - [x] 3.1 Implement addObserver method
    - Accept AppChangeCallback closure
    - Generate unique UUID for observer
    - Store in state.observers dictionary with lock protection
    - Return UUID for later removal
    - _Requirements: 5.1, 5.4_

  - [x] 3.2 Implement removeObserver method
    - Accept UUID parameter
    - Remove from state.observers dictionary with lock protection
    - Handle invalid UUID gracefully (idempotent)
    - _Requirements: 5.2_

  - [x] 3.3 Implement notification dispatch
    - Create scheduleWorkspaceRefresh method
    - Create refreshAndNotifyObservers method
    - Dispatch callbacks on callbackQueue
    - Handle thread-safe observer iteration with lock
    - _Requirements: 1.2, 5.3, 5.4_

  - [x] 3.4 Write unit tests for observer operations
    - Test addObserver returns valid UUID
    - Test removeObserver removes the correct observer
    - Test multiple observers can be registered
    - _Requirements: 5.1, 5.2, 5.4_

  - [ ]* 3.5 Write property test for observer registration
    - **Property 7: Observer Registration**
    - **Validates: Requirements 5.1**

  - [ ]* 3.6 Write property test for observer unregistration
    - **Property 8: Observer Unregistration**
    - **Validates: Requirements 5.2**

- [x] 4. Implement self-app exclusion feature
  - [x] 4.1 Implement setExcludedBundleID method
    - Accept optional String parameter
    - Store in state.excludedBundleID property with lock protection
    - _Requirements: 6.1_

  - [x] 4.2 Update resolveCurrentApp to handle exclusion logic
    - Check if frontmost app matches state.excludedBundleID
    - Return state.previousApp when excluded
    - Track previous app in state for fallback
    - _Requirements: 6.1, 6.2_

  - [x] 4.3 Write unit tests for exclusion behavior
    - Test setExcludedBundleID configures exclusion
    - Test excluded app returns nil or previous app
    - _Requirements: 6.1, 6.2_

  - [ ]* 4.4 Write property test for exclusion behavior
    - **Property 10: Exclusion Behavior**
    - **Validates: Requirements 6.1, 6.2**

- [x] 5. Implement workspace notification handling
  - [x] 5.1 Create workspace refresh handler
    - Implement scheduleWorkspaceRefresh method
    - Query workspace.frontmostApplication snapshot
    - Apply exclusion logic via resolveCurrentApp
    - Trigger observer notifications via refreshAndNotifyObservers
    - _Requirements: 2.1, 2.2_

  - [x] 5.2 Register for workspace notifications via protocol
    - Call workspace.observeFrontmostApplicationChanges in startMonitoring
    - Store observation token in state
    - Call workspace.removeObservation in stopMonitoring
    - Ensure proper memory management
    - _Requirements: 2.2, 2.3_

  - [x] 5.3 Write integration tests for notification handling
    - Test that app switches trigger observers
    - Test notification within 500ms latency
    - _Requirements: 2.1, 2.2_

  - [ ]* 5.4 Write property test for continuous monitoring
    - **Property 12: Continuous Monitoring**
    - **Validates: Requirements 2.2, 2.3**

- [x] 6. Implement thread safety and error handling
  - [x] 6.1 Add thread-safe state management
    - Use NSRecursiveLock (stateLock) for all state access
    - Implement withLock helper extension
    - Ensure concurrent access doesn't cause race conditions
    - Dispatch callbacks on callbackQueue
    - _Requirements: 3.2, 3.3, 11_

  - [x] 6.2 Implement error handling
    - Handle nil frontmost application gracefully with logging
    - Handle missing bundle identifier with logging
    - Log errors when monitor is deallocated during operations
    - Maintain consistent state on failures
    - _Requirements: 3.1, 3.4_

  - [x] 6.3 Write error handling tests
    - Test nil frontmost app handling
    - Test safe state management
    - Test rapid start/stop resilience
    - _Requirements: 3.3, error handling_

  - [ ]* 6.4 Write property test for thread safety
    - **Property 11: Thread Safety**
    - **Validates: Requirements 3.3**

- [x] 7. Checkpoint - Ensure all tests pass
  - ✅ All implemented tests pass
  - ✅ Core functionality verified
  - ✅ Error handling validated

- [ ] 8. Property-based tests for correctness
  - [ ]* 8.1 Write property test for current app retrieval
    - **Property 1: Current App Retrieval**
    - **Validates: Requirements 1.1, 1.3, 1.4**

  - [ ]* 8.2 Write property test for observer notification
    - **Property 2: Observer Notification**
    - **Validates: Requirements 1.2, 5.3, 5.4**

  - [ ]* 8.3 Write property test for bundle ID availability
    - **Property 3: Bundle ID Availability**
    - **Validates: Requirements 1.3**

  - [ ]* 8.4 Write property test for localized name availability
    - **Property 4: Localized Name Availability**
    - **Validates: Requirements 1.4**

  - [ ]* 8.5 Write property test for PID retrieval
    - **Property 5: PID Retrieval**
    - **Validates: Requirements 4.2**

  - [ ]* 8.6 Write property test for host app detection
    - **Property 6: Host App Detection**
    - **Validates: Requirements 4.3, 6.2**

- [x] 9. Final checkpoint - Ensure all tests pass
  - ✅ All implemented tests pass
  - ✅ Core functionality complete
  - ✅ Ready for production use
  - Note: Property-based tests (marked with *) are optional for MVP

## Notes

- Tasks marked with `*` are optional property-based tests that can be skipped for MVP
- Each task references specific requirements for traceability
- Property tests validate universal correctness properties across all inputs (optional)
- Unit tests validate specific examples and edge cases (implemented)
- The module targets macOS 12.0+ and works with both SwiftUI and AppKit
- Testing uses Swift Testing framework with dependency injection for deterministic tests
- Workspace abstraction layer enables testing without relying on actual system state