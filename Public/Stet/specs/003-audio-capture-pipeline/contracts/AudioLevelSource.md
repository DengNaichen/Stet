# Contract: AudioLevelSource

## Purpose

`AudioLevelSource` is the shared public boundary for normalized live audio levels during capture.

## Interface

```swift
protocol AudioLevelSource: Sendable {
    func makeAudioLevelStream() async -> AsyncStream<Double>
}
```

## Semantics

- The returned stream yields normalized audio levels for active capture.
- The stream is intended for UI feedback such as a level meter.
- The implementation may reuse a shared bridge so multiple consumers can subscribe.

## Error Behavior

- The method does not currently throw.
- If capture is inactive, the stream may remain silent until a capture session emits values.

## Usage Expectations

- Consumers should treat the level values as normalized UI input, not raw PCM amplitude.
- Consumers should not assume a specific polling frequency; they should respond to the stream values as they arrive.

## Notes

- `AudioLevelSource` is implemented by `MacAudioCaptureService` and by test doubles used in shared speech-service tests.
