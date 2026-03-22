# Implementation Plan: Audio Device Management

## Overview

This implementation plan breaks down the audio-device-management feature into discrete coding tasks. The feature adds comprehensive audio device enumeration, selection, persistence, and quality-based prioritization to the Stet macOS application.

Implementation approach:

- Start with core device management infrastructure
- Add device selection logic with quality scoring
- Integrate device monitoring for hot-plug support
- Wire into existing recording pipeline
- Add UI components for settings and menu bar
- Implement microphone testing functionality
- Integrate into onboarding flow
- Add comprehensive testing throughout

### Swift 6 Concurrency Architecture Findings
*Note: The interfaces have been prototyped and pre-compiled against strict concurrency rules.*
1. **Default Initializers in `@MainActor`**: Do not use default instantiations (e.g., `= DefaultAudioTestService()`) in the initializers of `@MainActor` classes if they might be called from non-isolated contexts. Inject dependencies explicitly at the call site (e.g., `static let shared = AudioDeviceSelectionManager(provider: SystemAudioDeviceProvider())`).
2. **Orthodox `nonisolated` Property Access**: Inside `AudioDeviceSelectionManager` (`@MainActor`), the `nonisolated func currentRecordingDevice()` cannot read a standard stored property directly. Instead of using a hacky external wrapper class, use the standard Swift 6 pattern: declare the property as `nonisolated(unsafe) private var _cachedRecordingDevice: AudioHardwareDevice?` and protect all read/write accesses manually with an `NSLock`. This satisfies strict concurrency in the most pure and idiomatic way.
3. **Access Control**: Protocol interfaces like `AudioDeviceProviding` should remain `internal` since the models they return (`AudioHardwareDevice`) are `internal`.

## Tasks

- [x] 1. Extend AudioInputDeviceManager with device enumeration
  - [x] 1.1 Implement allInputDevices() method
    - Query CoreAudio for all audio devices
    - Filter devices to only include those with input channels
    - Return array of AudioHardwareDevice instances
    - Handle CoreAudio API errors gracefully (return empty array on failure)
    - _Requirements: 1.1, 1.3, 1.4_
  
  - [x] 1.2 Implement inputDevice(id:) method
    - Query CoreAudio for device by AudioDeviceID
    - Return AudioHardwareDevice if device exists and has input channels
    - Return nil if device doesn't exist or has no input channels
    - _Requirements: 1.2_
  
  - [x] 1.3 Implement inputDevice(uid:) method
    - Query CoreAudio to find device by UID string
    - Return AudioHardwareDevice if device exists and has input channels
    - Return nil if device doesn't exist
    - _Requirements: 3.1, 3.3_
  
  - [x] 1.4 Implement hasInputChannels(deviceID:) helper method
    - Query CoreAudio for device input channel count
    - Return true if device has at least one input channel
    - Return false otherwise or on error
    - _Requirements: 1.5_
  
  - [ ]* 1.5 Write unit tests for AudioInputDeviceManager extensions
    - Test allInputDevices returns non-empty array on systems with microphones
    - Test device lookup by ID and UID
    - Test hasInputChannels validation
    - Test error handling for invalid IDs/UIDs
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5_

- [x] 2. Add AudioHardwareDevice automatic selection priority extension
  - [x] 2.1 Implement automaticSelectionPriority computed property
    - Return .builtIn (500) for built-in devices
    - Return .externalProfessional (400) for USB/PCI/FireWire devices
    - Return .unknownExternal (350) for unknown external devices
    - Return .virtual (300) for virtual devices
    - Return .airPlay (250) for AirPlay devices
    - Return .aggregate (200) for aggregate devices
    - Return .bluetooth (100) for Bluetooth/BluetoothLE devices
    - Return .handheldAppleDevice (50) for iPhone/iPad devices
    - _Requirements: 4.2, 4.3_
  
  - [x] 2.2 Implement isBluetooth computed property
    - Return true if transportType is Bluetooth or BluetoothLE
    - Return false otherwise
    - _Requirements: 4.2_
  
  - [x] 2.3 Implement isBuiltIn computed property
    - Return true if transportType is BuiltIn
    - Return false otherwise
    - _Requirements: 4.3_
  
  - [x] 2.4 Implement isHandheldAppleDevice computed property
    - Check if device name contains "iphone" or "ipad" (case-insensitive)
    - Return true if matched, false otherwise
    - _Requirements: 4.2_
  
  - [ ]* 2.5 Write property test for priority ordering
    - **Property 9: Priority reflects transport type ordering**
    - **Validates: Requirements 4.2**
    - Test that built-in devices always have higher priority than Bluetooth
    - Test that external professional devices have higher priority than Bluetooth
    - Use swift-check to generate random device combinations

- [x] 3. Create AudioDeviceSelectionManager
  - [x] 3.1 Define AudioDeviceProviding protocol
    - Create protocol with allInputDevices() and defaultInputDevice() methods
    - Mark protocol as Sendable for concurrency safety
    - _Requirements: 3.1, 4.3_
  
  - [x] 3.2 Implement SystemAudioDeviceProvider
    - Implement AudioDeviceProviding protocol
    - Delegate to AudioInputDeviceManager methods
    - _Requirements: 3.1_
  
  - [x] 3.3 Implement AudioDeviceSelectionManager core structure
    - Create @MainActor class conforming to ObservableObject
    - Add provider dependency (AudioDeviceProviding)
    - Add @Published selectedDevice property
    - Add @Published availableDevices array
    - Add @Published strategy property (automatic/manual)
    - Add @Published preferredDeviceUID property
    - Add thread-safe recording device cache with NSLock
    - Create shared singleton instance
    - _Requirements: 3.1, 3.2, 5.1, 5.2_
  
  - [x] 3.4 Implement device persistence with UserDefaults
    - Define MacPreferences keys for strategy and preferredDeviceUID
    - Load saved strategy and preferredDeviceUID in init
    - Save strategy changes to UserDefaults in didSet
    - Save preferredDeviceUID changes to UserDefaults in didSet
    - Handle UserDefaults read/write failures gracefully
    - _Requirements: 3.1, 3.4_
  
  - [x] 3.5 Implement refreshDevices() method
    - Call provider.allInputDevices()
    - Update availableDevices property
    - Re-evaluate selectedDevice based on current strategy
    - Update thread-safe recording device cache
    - _Requirements: 1.3, 1.4_
  
  - [x] 3.6 Implement selectDefaultDevice(from:) private method
    - Prioritize built-in device if available
    - Fall back to system default device if no built-in device
    - Otherwise select device with highest automaticSelectionPriority
    - Return nil if array is empty
    - _Requirements: 4.3_
  
  - [x] 3.7 Implement deviceForRecording() method
    - If strategy is .automatic, return selectDefaultDevice(from: availableDevices)
    - If strategy is .manual and preferredDeviceUID is set, find device by UID in availableDevices
    - If manual device not found, fall back to provider.defaultInputDevice()
    - Return nil if no devices available
    - _Requirements: 3.2, 3.3, 4.3, 5.2_
  
  - [x] 3.8 Implement selectDevice(_:) method
    - Set strategy to .manual
    - Set preferredDeviceUID to device.uid
    - Update selectedDevice to the provided device
    - Persist changes via UserDefaults
    - _Requirements: 5.2, 5.4_
  
  - [x] 3.9 Implement resetToAutomatic() method
    - Set strategy to .automatic
    - Clear preferredDeviceUID
    - Re-evaluate selectedDevice using quality scoring
    - Persist changes via UserDefaults
    - _Requirements: 4.3_
  
  - [x] 3.10 Implement currentRecordingDevice() nonisolated method
    - Lock recordingDeviceLock
    - Read _cachedRecordingDevice
    - Unlock and return cached device
    - Allows synchronous access from non-MainActor contexts
    - _Requirements: 3.2_
  
  - [ ]* 3.11 Write unit tests for AudioDeviceSelectionManager
    - Test automatic mode selects built-in device when available
    - Test automatic mode falls back to highest priority device
    - Test manual selection persists across manager instances
    - Test fallback to default device when preferred device unavailable
    - Test device selection can be changed multiple times
    - Test strategy switching between automatic and manual
    - Use mock AudioDeviceProviding for isolated testing
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 4.3, 5.2, 5.4_
  
  - [ ]* 3.12 Write property test for automatic mode selection
    - **Property 10: Automatic mode selects highest priority device**
    - **Validates: Requirements 4.3**
    - Generate random device arrays with swift-check
    - Verify deviceForRecording() always returns device with max automaticSelectionPriority
  
  - [ ]* 3.13 Write property test for manual selection override
    - **Property 11: Manual selection overrides automatic priority**
    - **Validates: Requirements 5.3**
    - Generate device arrays with varying priorities
    - Verify manual selection returns chosen device even if lower priority
  
  - [ ]* 3.14 Write property test for device persistence
    - **Property 5: Device selection persists**
    - **Validates: Requirements 3.1**
    - Select random devices and verify preferredDeviceUID is saved
    - Create new manager instance and verify UID is restored

- [x] 4. Checkpoint - Core device management complete
  - Ensure all tests pass, ask the user if questions arise.

- [x] 5. Create AudioDeviceChangeMonitor
  - [x] 5.1 Implement AudioDeviceChangeMonitor structure
    - Create class with shared singleton
    - Define devicesDidChangeNotification constant
    - Add propertyListenerBlock storage
    - Add stateLock for thread safety
    - Add monitorClientCount for reference counting
    - Add isMonitoring flag
    - _Requirements: 1.3, 1.4_
  
  - [x] 5.2 Implement startMonitoring() method
    - Increment monitorClientCount with thread safety
    - Register CoreAudio property listener only on first call
    - Post devicesDidChangeNotification when devices change
    - Handle listener registration failures gracefully (log warning)
    - _Requirements: 1.3, 1.4_
  
  - [x] 5.3 Implement stopMonitoring() method
    - Decrement monitorClientCount with thread safety
    - Unregister CoreAudio property listener only when count reaches zero
    - Clean up listener block
    - _Requirements: 1.3, 1.4_
  
  - [x] 5.4 Implement deinit
    - Call stopMonitoring() to clean up resources
    - _Requirements: 1.3, 1.4_
  
  - [ ]* 5.5 Write unit tests for AudioDeviceChangeMonitor
    - Test startMonitoring doesn't crash
    - Test stopMonitoring can be called multiple times safely
    - Test notification is posted (using NotificationCenter observation)
    - _Requirements: 1.3, 1.4_

- [x] 6. Integrate AudioDeviceSelectionManager into MacAudioFileRecorder
  - [x] 6.1 Modify startRecording() to use selected device
    - Replace AudioInputDeviceManager.defaultInputDevice() call
    - Use AudioDeviceSelectionManager.shared.currentRecordingDevice()
    - Use nonisolated synchronous method to avoid async propagation
    - Handle nil device case (log error, use system default as fallback)
    - _Requirements: 3.2, 4.1, 4.3, 5.2_
  
  - [ ]* 6.2 Write integration test for recording with selected device
    - Test recording uses manually selected device
    - Test recording falls back to default if selected device unavailable
    - _Requirements: 3.2, 3.3, 5.2_

- [x] 7. Add device selection UI to MacGeneralSettingsView
  - [x] 7.1 Create AudioInputDeviceSettingsSection view
    - Add Section with "Audio Input Device" title
    - Add Picker for selection strategy (Default/Manual)
    - Bind picker to deviceManager.strategy with custom binding
    - Conditionally show device picker when strategy is .manual
    - Add device Picker bound to deviceManager.preferredDeviceUID with custom binding
    - Display current selected device name
    - Integrate MicrophoneTestView
    - _Requirements: 5.1, 5.2, 5.4, 7.1_
  
  - [x] 7.2 Integrate AudioInputDeviceSettingsSection into MacGeneralSettingsView
    - Add @ObservedObject reference to AudioDeviceSelectionManager.shared
    - Add AudioInputDeviceSettingsSection to settings view body
    - Position section appropriately in settings layout
    - _Requirements: 5.1_
  
  - [x] 7.3 Add device refresh on settings view appear
    - Call deviceManager.refreshDevices() in onAppear
    - Start AudioDeviceChangeMonitor when settings view appears
    - Stop monitor when settings view disappears
    - _Requirements: 1.3, 1.4, 5.1_
  
  - [x] 7.4 Add notification observer for device changes
    - Observe AudioDeviceChangeMonitor.devicesDidChangeNotification
    - Call deviceManager.refreshDevices() when notification received
    - Update UI to reflect new device list
    - _Requirements: 1.3, 1.4_

- [x] 8. Create microphone testing functionality
  - [x] 8.1 Define MicrophoneTestService protocol
    - Add startRecording() async throws method
    - Add stopRecording() async throws -> URL method
    - Add playRecording(at:) async throws method
    - Add stopPlayback() method
    - Inherit from AudioLevelSource for audio level streaming
    - Mark protocol as @MainActor
    - _Requirements: 7.1, 7.2, 7.3, 7.4_
  
  - [x] 8.2 Implement DefaultMicrophoneTestService
    - Create class conforming to MicrophoneTestService and AVAudioPlayerDelegate
    - Add AudioCaptureService & AudioLevelSource dependency
    - Add AVAudioPlayer storage for playback
    - Add playbackContinuation for async playback
    - _Requirements: 7.1, 7.2, 7.3_
  
  - [x] 8.3 Implement startRecording() in DefaultMicrophoneTestService
    - Stop any ongoing playback
    - Start AudioCaptureService
    - Activate recording window
    - _Requirements: 7.2, 7.4_
  
  - [x] 8.4 Implement stopRecording() in DefaultMicrophoneTestService
    - Stop AudioCaptureService
    - Return recording URL from result
    - _Requirements: 7.2_
  
  - [x] 8.5 Implement playRecording(at:) in DefaultMicrophoneTestService
    - Stop any ongoing playback
    - Create AVAudioPlayer with recording URL
    - Set delegate and prepare to play
    - Start playback
    - Use CheckedContinuation to await completion
    - _Requirements: 7.3_
  
  - [x] 8.6 Implement stopPlayback() in DefaultMicrophoneTestService
    - Stop AVAudioPlayer if playing
    - Clean up player instance
    - Resume continuation if waiting
    - _Requirements: 7.3_
  
  - [x] 8.7 Implement makeAudioLevelStream() in DefaultMicrophoneTestService
    - Delegate to captureService.makeAudioLevelStream()
    - Return AsyncStream<Double> with normalized levels
    - _Requirements: 7.4_
  
  - [x] 8.8 Implement AVAudioPlayerDelegate methods
    - audioPlayerDidFinishPlaying: clean up and resume continuation
    - audioPlayerDecodeErrorDidOccur: clean up and throw error
    - _Requirements: 7.3_
  
  - [ ]* 8.9 Write unit tests for DefaultMicrophoneTestService
    - Test recording creates file at expected URL
    - Test playback doesn't crash
    - Test stopPlayback can be called safely
    - Test audio level stream emits values
    - Use mock AudioCaptureService for isolation
    - _Requirements: 7.1, 7.2, 7.3, 7.4_

- [x] 9. Create MicrophoneTestViewModel
  - [x] 9.1 Implement MicrophoneTestViewModel structure
    - Create @MainActor class conforming to ObservableObject
    - Add @Published private(set) isRecording property
    - Add @Published private(set) isPlaying property
    - Add @Published private(set) audioLevel property
    - Add @Published private(set) hasRecording property
    - Add MicrophoneTestService dependency
    - Add recordingURL storage
    - Add audioLevelTask for observation
    - _Requirements: 7.1, 7.2, 7.3, 7.4_
  
  - [x] 9.2 Implement startRecording() method
    - Guard against already recording
    - Set isRecording to true
    - Call microphoneTestService.startRecording()
    - Start observing audio level stream
    - Update audioLevel property from stream
    - Handle errors gracefully (log and reset state)
    - _Requirements: 7.2, 7.4_
  
  - [x] 9.3 Implement stopRecording() method
    - Guard against not recording
    - Stop audio level stream observation
    - Call microphoneTestService.stopRecording()
    - Set isRecording to false
    - Set hasRecording to true
    - Store recording URL
    - Handle errors gracefully
    - _Requirements: 7.2_
  
  - [x] 9.4 Implement playRecording() method
    - Guard against no recording or already playing
    - Set isPlaying to true
    - Call microphoneTestService.playRecording(at: recordingURL)
    - Set isPlaying to false when playback completes (using defer)
    - Handle errors gracefully
    - _Requirements: 7.3_
  
  - [x] 9.5 Implement stopPlayback() method
    - Call microphoneTestService.stopPlayback()
    - Set isPlaying to false
    - _Requirements: 7.3_
  
  - [x] 9.6 Implement startAudioLevelObservation() private method
    - Cancel existing audioLevelTask
    - Create new Task that observes audio level stream
    - Update audioLevel property for each value
    - Handle task cancellation
    - _Requirements: 7.4_
  
  - [x] 9.7 Implement stopAudioLevelObservation() private method
    - Cancel audioLevelTask
    - Set audioLevelTask to nil
    - _Requirements: 7.4_
  
  - [ ]* 9.8 Write unit tests for MicrophoneTestViewModel
    - Test recording state transitions
    - Test playback state transitions
    - Test hasRecording flag updates correctly
    - Test audio level updates during recording
    - Use mock MicrophoneTestService for isolation
    - _Requirements: 7.1, 7.2, 7.3, 7.4_

- [x] 10. Create MicrophoneTestView
  - [x] 10.1 Implement MicrophoneAudioLevelMeter view
    - Create visual indicator for audio level (progress bar style)
    - Bind to viewModel.audioLevel
    - Animate level changes smoothly
    - _Requirements: 7.4_
  
  - [x] 10.2 Implement MicrophoneTestView structure
    - Create SwiftUI view with MicrophoneTestViewModel
    - Add MicrophoneAudioLevelMeter with fixed height
    - Add "Start/Stop Recording" button with Label
    - Bind button to viewModel.startRecording/stopRecording
    - Use .borderedProminent button style with dynamic tint
    - Disable button when playing
    - _Requirements: 7.2, 7.4_
  
  - [x] 10.3 Add playback controls to MicrophoneTestView
    - Add "Play/Stop Recording" button with Label
    - Bind button to viewModel.playRecording/stopPlayback
    - Use .bordered button style
    - Disable button when recording or no recording available
    - _Requirements: 7.3_
  
  - [x] 10.4 Add status indicators to MicrophoneTestView
    - Show success message with checkmark when hasRecording is true
    - Show recording indicator with ProgressView when isRecording is true
    - Use appropriate styling and colors
    - _Requirements: 7.1, 7.4_
  
  - [x] 10.5 Integrate MicrophoneTestView into AudioInputDeviceSettingsSection
    - Add MicrophoneTestView to settings section
    - Create MicrophoneTestViewModel instance with StateObject
    - Pass DefaultMicrophoneTestService.shared as dependency
    - _Requirements: 7.1_

- [~] 11. Checkpoint - Settings UI and testing complete
  - Ensure all tests pass, ask the user if questions arise.

- [x] 12. Create AudioInputDeviceMenuSection (SwiftUI)
  - [x] 12.1 Implement AudioInputDeviceMenuSection view
    - Create SwiftUI view conforming to View protocol
    - Add @ObservedObject reference to AudioDeviceSelectionManager (injected via init)
    - Use Section with "Audio Input Device" header
    - _Requirements: 6.1, 6.2_
  
  - [x] 12.2 Implement "Default" option button
    - Add Button that calls deviceManager.resetToAutomatic()
    - Show "Default (Built-in Microphone)" as label
    - Use menuRow helper with checkmark when strategy is .automatic
    - _Requirements: 6.2, 6.3_
  
  - [x] 12.3 Implement device list with ForEach
    - Iterate through deviceManager.availableDevices using ForEach
    - Use device.uid as identifier
    - Create Button for each device with device name as label
    - Use menuRow helper with checkmark for currently selected device
    - Show checkmark when strategy is .manual and device matches selectedDevice
    - _Requirements: 6.2, 6.3_
  
  - [x] 12.4 Implement device selection action
    - Add Button action closure that calls deviceManager.selectDevice(device)
    - Action automatically updates selectedDevice via @Published property
    - _Requirements: 6.4_
  
  - [x] 12.5 Add automatic UI refresh via notification
    - Observe AudioDeviceChangeMonitor.devicesDidChangeNotification
    - Call deviceManager.refreshDevices() when notification received
    - SwiftUI automatically refreshes when @Published properties change
    - _Requirements: 6.5_
  
  - [x] 12.6 Implement menuRow helper view
    - Create private function returning HStack with text and optional checkmark
    - Accept title and isSelected parameters
    - Show checkmark Image when isSelected is true
    - _Requirements: 6.3_
  
  - [ ]* 12.7 Write unit tests for AudioInputDeviceMenuSection
    - Test view renders correct number of devices
    - Test selected device shows checkmark
    - Test button action calls selectDevice
    - Use mock AudioDeviceSelectionManager for isolation
    - _Requirements: 6.2, 6.3, 6.4_

- [x] 13. Integrate AudioInputDeviceMenuSection into MacMenuBarView
  - [x] 13.1 Add AudioInputDeviceMenuSection to MacMenuBarView
    - Open Stet/Features/MacShell/MacMenuBarView.swift
    - Add AudioInputDeviceMenuSection() at the top of the menu
    - Add Divider() after the section
    - Position before existing "Settings…" button
    - _Requirements: 6.1_  
  - [x] 13.2 Device refresh handled by AudioInputDeviceMenuSection
    - AudioInputDeviceMenuSection observes device change notifications internally
    - No need for additional refresh logic in MacMenuBarView
    - _Requirements: 6.5_

- [ ] 14. Create OnboardingMicrophoneTestView
  - [~] 14.1 Implement OnboardingMicrophoneTestView structure
    - Create SwiftUI view with MicrophoneTestViewModel
    - Add @Binding canProceed property
    - Add title "Test Your Microphone"
    - Add descriptive text about testing
    - Embed MicrophoneTestView
    - _Requirements: 8.1, 8.2, 8.3_
  
  - [~] 14.2 Add success indicator
    - Show checkmark icon when hasRecording is true
    - Show "Microphone test successful!" message
    - Update canProceed binding when test succeeds
    - _Requirements: 8.4_
  
  - [~] 14.3 Add error handling and guidance
    - Show helpful message if recording fails
    - Provide troubleshooting tips (check permissions, device connection)
    - Allow retry
    - _Requirements: 8.5_
  
  - [~] 14.4 Integrate into onboarding flow
    - Add OnboardingMicrophoneTestView to onboarding sequence
    - Position after permissions step
    - Wire canProceed to next button state
    - _Requirements: 8.1_

- [ ] 15. Add comprehensive property-based tests
  - [ ]* 15.1 Write property test for device persistence
    - **Property 5: Device selection persists**
    - **Validates: Requirements 3.1**
    - Generate random device selections
    - Verify preferredDeviceUID persists across manager instances
  
  - [ ]* 15.2 Write property test for manual device selection
    - **Property 6: Manual selection is used**
    - **Validates: Requirements 3.2, 5.2**
    - Generate random device and set as manual selection
    - Verify deviceForRecording() returns that device
  
  - [ ]* 15.3 Write property test for device unavailable fallback
    - **Property 7: Fallback to default when unavailable**
    - **Validates: Requirements 3.3**
    - Set preferredDeviceUID to non-existent UID
    - Verify deviceForRecording() returns default device
  
  - [ ]* 15.4 Write property test for multiple selection changes
    - **Property 8: Selection can change multiple times**
    - **Validates: Requirements 3.4, 5.4**
    - Generate sequence of device selections
    - Verify final selection matches last device
  
  - [ ]* 15.5 Write property test for recording device switching
    - **Property 12: Recording uses new device after switch**
    - **Validates: Requirements 7.5**
    - Select device A, verify it's used for recording
    - Select device B, verify it's used for next recording

- [ ] 16. Add hardware integration tests
  - [ ]* 16.1 Write integration test for device enumeration
    - **Property 1: All devices have non-empty names**
    - **Validates: Requirements 1.2**
    - Test allInputDevices() returns devices with valid names
    - Test on real hardware (not mocked)
  
  - [ ]* 16.2 Write integration test for device list accuracy
    - **Property 2: Device list reflects hardware state**
    - **Validates: Requirements 1.3, 1.4**
    - Test refreshDevices() updates availableDevices
    - Test list contains only devices with input channels
  
  - [ ]* 16.3 Write integration test for default device availability
    - **Property 3: Default device always available**
    - **Validates: Requirements 1.5**
    - Test defaultInputDevice() is in allInputDevices()
    - Test on real hardware

  - [ ]* 16.4 Write integration test for device UID uniqueness
    - **Property 4: Device UID uniqueness**
    - **Validates: Requirements 2.3**
    - Test allInputDevices() returns devices with unique UIDs
    - Test on real hardware

- [~] 17. Final checkpoint - Complete feature verification
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional testing tasks and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Property-based tests use swift-check library with XCTest
- Unit tests use Swift Testing framework
- Hardware integration tests run against real CoreAudio APIs
- UI components (Views) are not unit tested, only ViewModels
- All business logic is thoroughly tested with both unit and property tests
- Checkpoints ensure incremental validation at key milestones
