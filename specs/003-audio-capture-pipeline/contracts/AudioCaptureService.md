# Contract: AudioCaptureService

## Purpose

`AudioCaptureService` is the shared public capture boundary used by dictation and microphone test consumers.

## Interface

```swift
protocol AudioCaptureService: Sendable {
    func startRecording() async throws
    func activateRecordingWindow() async throws
    func stopRecording() async throws -> (url: URL, duration: TimeInterval?)
    func cancelRecording() async
    func prewarm() async
}
```

## Semantics

- `startRecording()` begins a new capture session and may request microphone permission.
- `activateRecordingWindow()` enables writing of buffered audio; it requires an active recording session.
- `stopRecording()` finalizes capture and returns the temporary output file and duration when available.
- `cancelRecording()` abandons the active session and discards temporary output.
- `prewarm()` allows the implementation to initialize capture-related state ahead of time.

## Error Behavior

- Starting while already recording should fail with an already-recording error.
- Permission denial should fail before a recording file is treated as valid capture output.
- Invalid lifecycle transitions should fail with a not-recording error or equivalent capture error from the implementation.
- Capture startup failures should surface as a start failure to the consumer.

## Usage Expectations

- Consumers should treat the returned file URL as temporary capture output.
- Consumers should stop or cancel the session before starting another recording.
- Consumers that need buffered pre-activation audio should call `activateRecordingWindow()` after `startRecording()`.

## Notes

- The macOS implementation is `MacAudioCaptureService`.
- This contract is consumed by dictation and microphone test flows, not by internal recorder helpers.
