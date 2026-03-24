# Stet

English | [中文](docs/README.zh-CN.md)

Stet is a macOS menu bar dictation app that turns speech into usable text with minimal rewriting.

## About

Stet records speech, transcribes it, and can paste the result back into the current app or replace selected text. The app stays in the menu bar, starts from a global hotkey, and aims to keep the transcript close to the speaker's intent.

## Features

- Menu bar only, with no Dock presence
- Global hotkey to start and stop dictation
- Microphone testing and input device selection
- OpenAI and Groq transcription providers
- `Automatic`, `Stet account`, and `Your own key` execution modes
- Chinese, English, and mixed Chinese-English dictation preferences
- Personal dictionary support
- Sparkle-based automatic updates

## Requirements

- macOS 26.0 or later
- Xcode 26 or a compatible version
- Microphone permission
- Accessibility / input control permission so Stet can write text into other apps

## Getting Started

Open `apps/mac/Stet.xcodeproj` in Xcode, let Swift Package dependencies resolve, then run the `Stet` scheme.

Or build from the repository root:

```bash
npm run mac:build
```

Or call `xcodebuild` directly:

```bash
xcodebuild -project apps/mac/Stet.xcodeproj -scheme Stet -configuration Debug -destination 'platform=macOS' build
```

## Configuration

On first launch, Stet guides you through permissions, dictation setup, and either a Stet account or your own API key. Settings also cover audio input, language preference, appearance, updates, and the personal dictionary.

## Troubleshooting

### Debug build does not show the microphone permission prompt

If `Stet Debug` does not appear in System Settings and clicking `Request Access` does not show the macOS microphone prompt, check the Debug build configuration first.

- `ENABLE_RESOURCE_ACCESS_AUDIO_INPUT` must be `YES` for the Debug app
- the built app should contain `com.apple.security.device.audio-input` in its generated entitlements
- without that entitlement, `tccd` rejects the request before showing a prompt

### Local builds and installed apps must not share the same identity

Do not use the same bundle identifier for local Xcode builds and the installed `/Applications/Stet.app`.

- `Debug` uses `NaichengDeng.Stet.Debug`
- local `./scripts/build-macos-release.sh` now uses `NaichengDeng.Stet.LocalRelease`
- shipped / notarized Release uses `NaichengDeng.Stet`

Keeping these separate avoids TCC and Launch Services collisions across microphone permission, Accessibility permission, and OAuth callback handling.

If you previously launched a local Release build signed with Apple Development using `NaichengDeng.Stet`, macOS may have stored Accessibility consent for the wrong code requirement. In that case the installed Developer ID app can still show as enabled in System Settings but fail `AXIsProcessTrusted()` at runtime.

### Onboarding still shows microphone access as blocked after Allow

If the system prompt appears, permission is granted, and `Stet Debug` shows up in System Settings, but onboarding still refuses to continue, the problem is usually in the app-side permission gate rather than macOS TCC.

- request microphone permission with `AVAudioApplication.requestRecordPermission`
- read microphone status from `AVAudioApplication.shared.recordPermission`
- avoid mixing `AVCaptureDevice.authorizationStatus(for: .audio)` with `AVAudioApplication` for gate decisions

The capture pipeline can still use the existing macOS audio capture backend. Only the permission request and permission status checks need to stay on the same API family.

## Testing

Run the macOS test suite:

```bash
xcodebuild -project apps/mac/Stet.xcodeproj -scheme Stet -destination 'platform=macOS' test
```

## Release

Build a local Release app bundle:

```bash
./scripts/build-macos-release.sh
```

Build the signed and notarized GitHub release artifacts:

```bash
./scripts/release-macos-github.sh
./scripts/publish-github-release.sh
```

Release artifacts are written to `dist/github-release/<tag>/`.

## Documentation

- Chinese version: [docs/README.zh-CN.md](docs/README.zh-CN.md)

## License

Apache-2.0
