# Implementation Plan: Permission Management

## Overview

This implementation adds a minimal runtime permission-failure window to handle blocked dictation actions when required permissions are missing. The implementation consists of three core components: RuntimePermissionFailureViewModel, RuntimePermissionFailureView, and MacPermissionGateController window implementation.

## Tasks

- [ ] 1. Create RuntimePermissionFailureViewModel
  - [x] 1.1 Implement RuntimePermissionFailureViewModel with coordinator observation
    - Create `apps/mac/Stet/App/Windowing/RuntimePermissionFailureViewModel.swift`
    - Add `@Published private(set) var shouldDismiss` property
    - Subscribe to `coordinator.updates` publisher
    - Implement `hasRequiredPermissions` computed property checking both microphone and auto-paste access
    - Implement `messageText`, `microphoneButtonTitle`, and `inputControlButtonTitle` properties
    - Implement `resolveMicrophoneAccess()` and `requestInputControlAccess()` methods
    - _Requirements: 2.3, 2.4, 4.4_
  
  - [ ]* 1.2 Write unit tests for RuntimePermissionFailureViewModel
    - Test that `shouldDismiss` becomes true when permissions are restored
    - Test that recovery actions forward to coordinator correctly
    - Test that `hasRequiredPermissions` reflects coordinator state
    - _Requirements: 2.3, 2.4, 4.4_

- [ ] 2. Create RuntimePermissionFailureView
  - [x] 2.1 Implement RuntimePermissionFailureView SwiftUI component
    - Create `apps/mac/Stet/App/Windowing/RuntimePermissionFailureView.swift`
    - Add title "Permissions Required"
    - Add explanatory text using `viewModel.messageText`
    - Add microphone recovery button calling `viewModel.resolveMicrophoneAccess()`
    - Add input control recovery button calling `viewModel.requestInputControlAccess()`
    - Set frame width to 420 points with 24-point padding
    - Add `.onReceive` modifier to call `onDismiss()` when `viewModel.shouldDismiss` becomes true
    - _Requirements: 2.3, 2.4, 6.1, 6.7_

- [ ] 3. Implement MacPermissionGateController window management
  - [x] 3.1 Implement MacPermissionGateController.show() method
    - Update `apps/mac/Stet/App/Windowing/MacPermissionGateController.swift`
    - Add `windowController` and `viewModel` private properties
    - Implement duplicate window prevention (return early if window already exists)
    - Create RuntimePermissionFailureViewModel instance
    - Create RuntimePermissionFailureView with dismiss closure
    - Create NSHostingController wrapping the view
    - Create NSWindow with floating level, titled and closable style mask
    - Center window and activate app
    - _Requirements: 2.5, 6.1, 6.2_
  
  - [x] 3.2 Implement MacPermissionGateController.hide() method
    - Close window controller
    - Clear window controller and view model references
    - _Requirements: 6.3_
  
  - [ ]* 3.3 Write unit tests for MacPermissionGateController
    - Test that duplicate calls to `show()` reuse existing window
    - Test that `hide()` cleans up window references
    - _Requirements: 2.5_

- [ ] 4. Checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 5. Verify MacAppSessionController integration
  - [ ] 5.1 Review existing permission gate trigger points
    - Verify `MacAppSessionController.presentRequiredPermissionsGateIfNeeded()` is called before dictation start
    - Verify gate is not presented during active recording or processing
    - Confirm gate presentation happens for hotkey and primary action triggers
    - _Requirements: 5.1, 5.2, 5.3, 5.6_
  
  - [ ]* 5.2 Write integration tests for permission gate triggers
    - Test that blocked hotkey action shows runtime window
    - Test that blocked primary action shows runtime window
    - Test that gate does not appear during active dictation
    - Test that restored permissions auto-close the runtime window
    - _Requirements: 2.1, 2.2, 2.6, 4.5_

- [ ] 6. Final checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- The design uses Swift and integrates with existing SwiftUI/AppKit architecture
- The implementation reuses existing `MacPermissionsCoordinating` protocol
- No changes to onboarding flow are required for this minimal runtime window
- Window auto-dismisses when permissions are restored via coordinator updates
