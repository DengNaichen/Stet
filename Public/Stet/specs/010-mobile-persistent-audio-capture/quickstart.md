# StetMobile Persistent Audio Capture Quickstart

Start with [spec.md](./spec.md), then use [plan.md](./plan.md) for implementation boundaries.

The production policy is created in `StetMobileApp.swift` as one `PersistentASRAudioCapture(strategy: .builtInPreferred)`. The shared frame, strategy, route resolution, lifecycle, AVAudioSession configuration, AVAudioEngine tap, conversion, and recovery live in `ASRAudioCapture.swift`. Recognition-specific processing remains in `SherpaOnnxASREngine.swift` and `FunASRRealtimeEngine.swift`.

Automated coverage lives in `StetMobileTests`. Physical-device acceptance must exercise both recognition engines while moving AirPods between the iPhone and another Apple device.
