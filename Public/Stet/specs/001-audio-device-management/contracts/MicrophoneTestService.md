# Contract: MicrophoneTestService

## Purpose

Defines the interface used by the Settings microphone test flow to record, observe levels, and play back a short audio sample.

## Consumers

- `MicrophoneTestViewModel`
- Any future UI that wants to reuse the Settings microphone test behavior

## Surface

```swift
@MainActor
protocol MicrophoneTestService: AnyObject, AudioLevelSource {
    func startRecording() async throws
    func stopRecording() async throws -> URL
    func playRecording(at url: URL) async throws
    func stopPlayback()
}
```

## Contract Guarantees

### startRecording()

**Preconditions**:
- No recording is already in progress in the consumer

**Behavior**:
- Starts capture for a short test sample
- Uses the application's current capture stack and selected audio route

**Postconditions**:
- Recording is active until `stopRecording()` completes or capture fails

### stopRecording()

**Preconditions**:
- A recording session is active

**Behavior**:
- Stops the current test recording

**Postconditions**:
- Returns the URL of the recorded sample file when capture succeeds

### playRecording(at:)

**Preconditions**:
- Caller provides a readable recording file URL

**Behavior**:
- Starts playback of the previously recorded sample
- Suspends until playback finishes or fails

### stopPlayback()

**Behavior**:
- Stops any active playback
- Is safe to call even if playback is not active

## Audio Level Stream

Because `MicrophoneTestService` conforms to `AudioLevelSource`, consumers may observe a live stream of normalized audio-level values while recording.

## Error Handling

- Recording-start and recording-stop failures propagate from the underlying capture service.
- Playback failures propagate as thrown errors.
- The default implementation also exposes a playback-specific error for failed local playback startup.

## Notes

- The current default implementation reuses `MacAudioCaptureService`, so microphone testing follows the same selected-device routing used by dictation.
- This contract describes the Settings microphone test behavior. It does not imply that onboarding currently implements the same end-to-end flow.
