# Stet

English | [中文](docs/README.zh-CN.md)

![Stet app icon](docs/assets/app-icon.png)

![Stet demo](docs/assets/demo.gif)

Stet is a macOS menu bar dictation app that turns speech into usable text with minimal rewriting.

This repository is the macOS app repository for Stet.

## About

Stet records speech, transcribes it, and can paste the result back into the current app or replace selected text. The app stays in the menu bar, starts from a global hotkey, and aims to keep the transcript close to the speaker's intent.

## Features

- Menu bar only, with no Dock presence
- Global hotkey to start and stop dictation
- Microphone testing and input device selection
- OpenAI and Groq transcription providers
- `Automatic`, `Stet account`, and `Your own key` execution modes
- Personal dictionary support
- Sparkle-based automatic updates

## Requirements

- macOS 26.0 or later
- Xcode 26 or a compatible version
- Microphone permission
- Accessibility / input control permission so Stet can write text into other apps

## Getting Started

Open `Stet.xcodeproj` in Xcode, let Swift Package dependencies resolve, then run the `Stet` scheme.

Or build from the repository root:

```bash
make build
```

Or call `xcodebuild` directly:

```bash
xcodebuild -project Stet.xcodeproj -scheme Stet -configuration Debug -destination 'platform=macOS' build
```

### Xcode storage

Use the repository storage doctor to see exactly how much space Stet, StetMobile, shared Xcode caches, SwiftPM downloads, archives, and simulator runtimes consume:

```bash
make doctor
```

After quitting Xcode and other Swift editors or build tools, remove only reproducible Stet and StetMobile build caches with:

```bash
make clean-derived-data
```

The cleanup command uses an explicit allowlist. It does not remove archives, signing data, models, downloaded frameworks, or simulator runtimes.

## Configuration

On first launch, Stet guides you through permissions, dictation setup, and either a Stet account or your own API key. Settings also cover audio input, appearance, updates, and the personal dictionary.

## Troubleshooting

### Debug build does not show the microphone permission prompt

If `Stet Debug` does not appear in System Settings and clicking `Request Access` does not show the macOS microphone prompt, check the Debug build configuration first.

- `ENABLE_RESOURCE_ACCESS_AUDIO_INPUT` must be `YES` for the Debug app
- the built app should contain `com.apple.security.device.audio-input` in its generated entitlements
- without that entitlement, `tccd` rejects the request before showing a prompt

### Local builds and installed apps must not share the same identity

Do not use the same bundle identifier for local Xcode builds and the installed `/Applications/Stet.app`.

- `Debug` uses `NaichengDeng.Stet.Debug`
- shipped / notarized Release uses `NaichengDeng.Stet`

Keeping these separate avoids TCC and Launch Services collisions across microphone permission, Accessibility permission, and OAuth callback handling.

If you previously launched a locally signed build using `NaichengDeng.Stet`, macOS may have stored Accessibility consent for the wrong code requirement. In that case the installed Developer ID app can still show as enabled in System Settings but fail `AXIsProcessTrusted()` at runtime.

### Onboarding still shows microphone access as blocked after Allow

If the system prompt appears, permission is granted, and `Stet Debug` shows up in System Settings, but onboarding still refuses to continue, the problem is usually in the app-side permission gate rather than macOS TCC.

- request microphone permission with `AVAudioApplication.requestRecordPermission`
- read microphone status from `AVAudioApplication.shared.recordPermission`
- avoid mixing `AVCaptureDevice.authorizationStatus(for: .audio)` with `AVAudioApplication` for gate decisions

The capture pipeline can still use the existing macOS audio capture backend. Only the permission request and permission status checks need to stay on the same API family.

## Testing

Run the macOS test suite:

```bash
xcodebuild -project Stet.xcodeproj -scheme Stet -destination 'platform=macOS' test
```

## Release

The engineering release flow for this repository is:

1. Do normal development locally and validate with `make build` and `make test`.
2. If you need a release-quality test build, run the `macOS Release Candidate` GitHub Actions workflow with a label such as `v0.0.10-rc1`.
3. Download the workflow artifact and verify install, launch, permissions, and update-related behavior from the CI-generated DMG.
4. When ready for a formal release, push a `v*` tag from the release commit on `main`.
5. Let the `macOS Release` GitHub Actions workflow generate the signed and notarized DMG, plus Sparkle appcast data.

Formal release artifacts are CI-generated only. The release process does not rely on local packaging or local release validation on a developer machine.

Current repository behavior:

- release-candidate builds on GitHub but does not publish a GitHub Release
- production release builds on GitHub, generates Sparkle appcast data, and publishes the GitHub Release from the same workflow

Release artifacts are written to `dist/github-release/<tag>/`.

## Documentation

- Chinese version: [docs/README.zh-CN.md](docs/README.zh-CN.md)
- Release guide: [docs/release.md](docs/release.md)
- 发布指南: [docs/release.zh-CN.md](docs/release.zh-CN.md)

## License

GPL-3.0-only
