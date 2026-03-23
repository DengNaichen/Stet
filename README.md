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
