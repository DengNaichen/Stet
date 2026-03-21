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
2. **`nonisolated` Property Access**: Inside `AudioDeviceSelectionManager` (`@MainActor`), the `nonisolated func currentRecordingDevice()` cannot read a stored property directly, even if wrapped in an `NSLock`. The locked variable must be extracted into an external `@unchecked Sendable` cache class (e.g., `ThreadSafeRecordingDeviceCache`) to satisfy the compiler.
3. **Access Control**: Protocol interfaces like `AudioDeviceProviding` should remain `internal` since the models they return (`AudioHardwareDevice`) are `internal`.

## Tasks

- [ ] 1. Extend AudioInputDeviceManager with device enumeration
  - [ ] 1.1 Implement allInputDevices() method
    - Query CoreAudio for all audio devices
    - Filter devices to only include those with input channels
    - Return array of AudioHardwareDevice instances
    - Handle CoreAudio API errors gracefully (return empty array on failure)
    - _Requirements: 1.1, 1.3, 1.4_
  
  - [ ] 1.2 Implement inputDevice(id:) method
    - Query CoreAudio for device by AudioDeviceID
    - Return AudioHardwareDevice if device exists and has input channels
    - Return nil if device doesn't exist or has no input channels
    - _Requirements: 1.2_
  
  - [ ] 1.3 Implement inputDevice(uid:) method
    - Query CoreAudio to find device by UID string
    - Return AudioHardwareDevice if device exists and has input channels
    - Return nil if device doesn't exist
    - _Requirements: 3.1, 3.3_
  
  - [ ] 1.4 Implement hasInputChannels(deviceID:) helper method
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

- [ ] 2. Add AudioHardwareDevice quality scoring extension
  - [ ] 2.1 Implement qualityScore computed property
    - Return 100 for USB/PCI/FireWire devices (external professional equipment)
    - Return 90 for built-in devices
    - Return 80 for virtual devices
    - Return 70 for AirPlay devices
    - Return 60 for aggregate devices
    - Return 20 for Bluetooth/BluetoothLE devices
    - Return 95 for unknown external devices (default high priority)
    - _Requirements: 4.2, 4.3_
  
  - [ ] 2.2 Implement isBluetooth computed property
    - Return true if transportType is Bluetooth or BluetoothLE
    - Return false otherwise
    - _Requirements: 4.2_
  
  - [ ]* 2.3 Write property test for quality scoring
    - **Property 9: Quality score reflects transport type priority**
    - **Validates: Requirements 4.2**
    - Test that USB/BuiltIn devices always score higher than Bluetooth
    - Test that external devices score >= built-in devices
    - Use swift-check to generate random device combinations

- [ ] 3. Create AudioDeviceSelectionManager
  - [ ] 3.1 Define AudioDeviceProviding protocol
    - Create protocol with allInputDevices() and defaultInputDevice() methods
    - Mark protocol as Sendable for concurrency safety
    - _Requirements: 3.1, 4.3_
  
  - [ ] 3.2 Implement SystemAudioDeviceProvider
    - Implement AudioDeviceProviding protocol
    - Delegate to AudioInputDeviceManager methods
    - _Requirements: 3.1_
  
  - [ ] 3.3 Implement AudioDeviceSelectionManager core structure
    - Create @MainActor class conforming to ObservableObject
    - Add provider dependency (AudioDeviceProviding)
    - Add @Published selectedDevice property
    - Add @Published availableDevices array
    - Add @Published strategy property (automatic/manual)
    - Add @Published preferredDeviceUID property
    - Add thread-safe recording device cache with NSLock
    - Create shared singleton instance
    - _Requirements: 3.1, 3.2, 5.1, 5.2_
  
  - [ ] 3.4 Implement device persistence with UserDefaults
    - Define MacPreferences keys for strategy and preferredDeviceUID
    - Load saved strategy and preferredDeviceUID in init
    - Save strategy changes to UserDefaults in didSet
    - Save preferredDeviceUID changes to UserDefaults in didSet
    - Handle UserDefaults read/write failures gracefully
    - _Requirements: 3.1, 3.4_
  
  - [ ] 3.5 Implement refreshDevices() method
    - Call provider.allInputDevices()
    - Update availableDevices property
    - Re-evaluate selectedDevice based on current strategy
    - Update thread-safe recording device cache
    - _Requirements: 1.3, 1.4_
  
  - [ ] 3.6 Implement selectBestQualityDevice(from:) private method
    - Find device with highest qualityScore from provided array
    - Return device with max score
    - Return nil if array is empty
    - _Requirements: 4.3_
  
  - [ ] 3.7 Implement deviceForRecording() method
    - If strategy is .automatic, return selectBestQualityDevice(from: availableDevices)
    - If strategy is .manual and preferredDeviceUID is set, find device by UID in availableDevices
    - If manual device not found, fall back to provider.defaultInputDevice()
    - Return nil if no devices available
    - _Requirements: 3.2, 3.3, 4.3, 5.2_
  
  - [ ] 3.8 Implement selectDevice(_:) method
    - Set strategy to .manual
    - Set preferredDeviceUID to device.uid
    - Update selectedDevice to the provided device
    - Persist changes via UserDefaults
    - _Requirements: 5.2, 5.4_
  
  - [ ] 3.9 Implement resetToAutomatic() method
    - Set strategy to .automatic
    - Clear preferredDeviceUID
    - Re-evaluate selectedDevice using quality scoring
    - Persist changes via UserDefaults
    - _Requirements: 4.3_
  
  - [ ] 3.10 Implement currentRecordingDevice() nonisolated method
    - Lock recordingDeviceLock
    - Read _cachedRecordingDevice
    - Unlock and return cached device
    - Allows synchronous access from non-MainActor contexts
    - _Requirements: 3.2_
  
  - [ ]* 3.11 Write unit tests for AudioDeviceSelectionManager
    - Test automatic mode selects highest quality device
    - Test manual selection persists across manager instances
    - Test fallback to default device when preferred device unavailable
    - Test device selection can be changed multiple times
    - Test strategy switching between automatic and manual
    - Use mock AudioDeviceProviding for isolated testing
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 4.3, 5.2, 5.4_
  
  - [ ]* 3.12 Write property test for automatic mode selection
    - **Property 10: Automatic mode selects highest quality device**
    - **Validates: Requirements 4.3**
    - Generate random device arrays with swift-check
    - Verify deviceForRecording() always returns device with max qualityScore
  
  - [ ]* 3.13 Write property test for manual selection override
    - **Property 11: Manual selection overrides quality priority**
    - **Validates: Requirements 5.3**
    - Generate device arrays with varying quality scores
    - Verify manual selection returns chosen device even if lower quality
  
  - [ ]* 3.14 Write property test for device persistence
    - **Property 5: Device selection persists**
    - **Validates: Requirements 3.1**
    - Select random devices and verify preferredDeviceUID is saved
    - Create new manager instance and verify UID is restored

- [ ] 4. Checkpoint - Core device management complete
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 5. Create AudioDeviceChangeMonitor
  - [ ] 5.1 Implement AudioDeviceChangeMonitor structure
    - Create class with shared singleton
    - Define devicesDidChangeNotification constant
    - Add propertyListenerBlock storage
    - _Requirements: 1.3, 1.4_
  
  - [ ] 5.2 Implement startMonitoring() method
    - Register CoreAudio property listener for device list changes
    - Post devicesDidChangeNotification when devices change
    - Handle listener registration failures gracefully (log warning)
    - _Requirements: 1.3, 1.4_
  
  - [ ] 5.3 Implement stopMonitoring() method
    - Unregister CoreAudio property listener
    - Clean up listener block
    - _Requirements: 1.3, 1.4_
  
  - [ ] 5.4 Implement deinit
    - Call stopMonitoring() to clean up resources
    - _Requirements: 1.3, 1.4_
  
  - [ ]* 5.5 Write unit tests for AudioDeviceChangeMonitor
    - Test startMonitoring doesn't crash
    - Test stopMonitoring can be called multiple times safely
    - Test notification is posted (using NotificationCenter observation)
    - _Requirements: 1.3, 1.4_

- [ ] 6. Integrate AudioDeviceSelectionManager into MacAudioFileRecorder
  - [ ] 6.1 Modify startRecording() to use selected device
    - Replace AudioInputDeviceManager.defaultInputDevice() call
    - Use AudioDeviceSelectionManager.shared.currentRecordingDevice()
    - Use nonisolated synchronous method to avoid async propagation
    - Handle nil device case (log error, use system default as fallback)
    - _Requirements: 3.2, 4.1, 4.3, 5.2_
  
  - [ ]* 6.2 Write integration test for recording with selected device
    - Test recording uses manually selected device
    - Test recording falls back to default if selected device unavailable
    - _Requirements: 3.2, 3.3, 5.2_

- [ ] 7. Add device selection UI to MacGeneralSettingsView
  - [ ] 7.1 Create AudioDeviceSettingsSection view
    - Add Section with "Audio Input Device" title
    - Add Picker for selection strategy (Automatic/Manual)
    - Bind picker to deviceManager.strategy
    - Conditionally show device picker when strategy is .manual
    - Add device Picker bound to deviceManager.preferredDeviceUID
    - Display current selected device name
    - _Requirements: 5.1, 5.2, 5.4_
  
  - [ ] 7.2 Integrate AudioDeviceSettingsSection into MacGeneralSettingsView
    - Add @ObservedObject reference to AudioDeviceSelectionManager.shared
    - Add AudioDeviceSettingsSection to settings view body
    - Position section appropriately in settings layout
    - _Requirements: 5.1_
  
  - [ ] 7.3 Add device refresh on settings view appear
    - Call deviceManager.refreshDevices() in onAppear
    - Start AudioDeviceChangeMonitor when settings view appears
    - Stop monitor when settings view disappears
    - _Requirements: 1.3, 1.4, 5.1_
  
  - [ ] 7.4 Add notification observer for device changes
    - Observe AudioDeviceChangeMonitor.devicesDidChangeNotification
    - Call deviceManager.refreshDevices() when notification received
    - Update UI to reflect new device list
    - _Requirements: 1.3, 1.4_

- [ ] 8. Create microphone testing functionality
  - [ ] 8.1 Define AudioTestService protocol
    - Add startRecording() async throws method
    - Add stopRecording() async throws -> URL method
    - Add playRecording(at:) async throws method
    - Add stopPlayback() method
    - Add makeAudioLevelStream() -> AsyncStream<Double> method
    - Mark protocol as @MainActor
    - _Requirements: 7.1, 7.2, 7.3, 7.4_
  
  - [ ] 8.2 Implement DefaultAudioTestService
    - Create class conforming to AudioTestService
    - Add AudioCaptureService dependency
    - Add AVAudioPlayer storage for playback
    - Add temporary recording URL storage
    - _Requirements: 7.1, 7.2, 7.3_
  
  - [ ] 8.3 Implement startRecording() in DefaultAudioTestService
    - Create temporary file URL for recording
    - Start AudioCaptureService with test configuration
    - Store recording URL
    - _Requirements: 7.2, 7.4_
  
  - [ ] 8.4 Implement stopRecording() in DefaultAudioTestService
    - Stop AudioCaptureService
    - Return recording URL
    - _Requirements: 7.2_
  
  - [ ] 8.5 Implement playRecording(at:) in DefaultAudioTestService
    - Create AVAudioPlayer with recording URL
    - Start playback
    - _Requirements: 7.3_
  
  - [ ] 8.6 Implement stopPlayback() in DefaultAudioTestService
    - Stop AVAudioPlayer if playing
    - Clean up player instance
    - _Requirements: 7.3_
  
  - [ ] 8.7 Implement makeAudioLevelStream() in DefaultAudioTestService
    - Create AsyncStream that emits audio level values
    - Connect to AudioCaptureService audio level updates
    - Normalize levels to 0.0-1.0 range
    - _Requirements: 7.4_
  
  - [ ]* 8.8 Write unit tests for DefaultAudioTestService
    - Test recording creates file at expected URL
    - Test playback doesn't crash
    - Test stopPlayback can be called safely
    - Test audio level stream emits values
    - Use mock AudioCaptureService for isolation
    - _Requirements: 7.1, 7.2, 7.3, 7.4_

- [ ] 9. Create MicrophoneTestViewModel
  - [ ] 9.1 Implement MicrophoneTestViewModel structure
    - Create @MainActor class conforming to ObservableObject
    - Add @Published isRecording property
    - Add @Published isPlaying property
    - Add @Published audioLevel property
    - Add @Published hasRecording property
    - Add AudioTestService dependency
    - _Requirements: 7.1, 7.2, 7.3, 7.4_
  
  - [ ] 9.2 Implement startRecording() method
    - Set isRecording to true
    - Call audioTestService.startRecording()
    - Start observing audio level stream
    - Update audioLevel property from stream
    - Handle errors gracefully (log and reset state)
    - _Requirements: 7.2, 7.4_
  
  - [ ] 9.3 Implement stopRecording() method
    - Call audioTestService.stopRecording()
    - Set isRecording to false
    - Set hasRecording to true
    - Stop audio level stream observation
    - Handle errors gracefully
    - _Requirements: 7.2_
  
  - [ ] 9.4 Implement playRecording() method
    - Set isPlaying to true
    - Call audioTestService.playRecording(at: recordingURL)
    - Set isPlaying to false when playback completes
    - Handle errors gracefully
    - _Requirements: 7.3_
  
  - [ ] 9.5 Implement stopPlayback() method
    - Call audioTestService.stopPlayback()
    - Set isPlaying to false
    - _Requirements: 7.3_
  
  - [ ]* 9.6 Write unit tests for MicrophoneTestViewModel
    - Test recording state transitions
    - Test playback state transitions
    - Test hasRecording flag updates correctly
    - Test audio level updates during recording
    - Use mock AudioTestService for isolation
    - _Requirements: 7.1, 7.2, 7.3, 7.4_

- [ ] 10. Create MicrophoneTestView
  - [ ] 10.1 Implement AudioLevelIndicator view
    - Create visual indicator for audio level (progress bar or waveform)
    - Bind to viewModel.audioLevel
    - Animate level changes smoothly
    - _Requirements: 7.4_
  
  - [ ] 10.2 Implement MicrophoneTestView structure
    - Create SwiftUI view with MicrophoneTestViewModel
    - Add AudioLevelIndicator
    - Add "Start/Stop Recording" button
    - Bind button to viewModel.startRecording/stopRecording
    - Disable button when playing
    - _Requirements: 7.2, 7.4_
  
  - [ ] 10.3 Add playback controls to MicrophoneTestView
    - Add "Play/Stop Recording" button
    - Bind button to viewModel.playRecording/stopPlayback
    - Disable button when recording or no recording available
    - _Requirements: 7.3_
  
  - [ ] 10.4 Integrate MicrophoneTestView into MacGeneralSettingsView
    - Add MicrophoneTestView to settings
    - Create MicrophoneTestViewModel instance
    - Position in appropriate section
    - _Requirements: 7.1_

- [ ] 11. Checkpoint - Settings UI and testing complete
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 12. Create MenuBarDeviceSwitcher
  - [ ] 12.1 Implement MenuBarDeviceSwitcher structure
    - Create @MainActor class
    - Add AudioDeviceSelectionManager dependency
    - _Requirements: 6.1, 6.2_
  
  - [ ] 12.2 Implement buildDeviceMenu() method
    - Create NSMenu instance
    - Iterate through deviceManager.availableDevices
    - Create NSMenuItem for each device with device name as title
    - Set representedObject to device.uid
    - Set state to .on for currently selected device
    - Set action to deviceSelected(_:)
    - Return menu
    - _Requirements: 6.2, 6.3_
  
  - [ ] 12.3 Implement deviceSelected(_:) action method
    - Extract device UID from sender.representedObject
    - Find device in availableDevices by UID
    - Call deviceManager.selectDevice(_:)
    - _Requirements: 6.4_
  
  - [ ] 12.4 Add menu refresh on device changes
    - Observe AudioDeviceChangeMonitor.devicesDidChangeNotification
    - Rebuild menu when devices change
    - Update checkmarks when selection changes
    - _Requirements: 6.5_
  
  - [ ]* 12.5 Write unit tests for MenuBarDeviceSwitcher
    - Test buildDeviceMenu creates correct number of items
    - Test selected device has checkmark
    - Test deviceSelected updates manager
    - Use mock AudioDeviceSelectionManager for isolation
    - _Requirements: 6.2, 6.3, 6.4_

- [ ] 13. Integrate MenuBarDeviceSwitcher into app menu bar
  - [ ] 13.1 Add device menu to MacAppModel or menu bar controller
    - Create MenuBarDeviceSwitcher instance
    - Add microphone submenu to menu bar
    - Update menu on app launch
    - _Requirements: 6.1_
  
  - [ ] 13.2 Add menu refresh on device changes
    - Start AudioDeviceChangeMonitor on app launch
    - Refresh menu when devices change notification received
    - _Requirements: 6.5_
  
  - [ ] 13.3 Add menu refresh on selection changes
    - Observe AudioDeviceSelectionManager.selectedDevice changes
    - Update menu checkmarks when selection changes
    - _Requirements: 6.3_

- [ ] 14. Create OnboardingMicrophoneTestView
  - [ ] 14.1 Implement OnboardingMicrophoneTestView structure
    - Create SwiftUI view with MicrophoneTestViewModel
    - Add @Binding canProceed property
    - Add title "Test Your Microphone"
    - Add descriptive text about testing
    - Embed MicrophoneTestView
    - _Requirements: 8.1, 8.2, 8.3_
  
  - [ ] 14.2 Add success indicator
    - Show checkmark icon when hasRecording is true
    - Show "Microphone test successful!" message
    - Update canProceed binding when test succeeds
    - _Requirements: 8.4_
  
  - [ ] 14.3 Add error handling and guidance
    - Show helpful message if recording fails
    - Provide troubleshooting tips (check permissions, device connection)
    - Allow retry
    - _Requirements: 8.5_
  
  - [ ] 14.4 Integrate into onboarding flow
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

- [ ] 17. Final checkpoint - Complete feature verification
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
