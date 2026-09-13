# Stet

[English](README.md) | [中文](docs/README.zh-CN.md)

![Stet app icon](docs/assets/app-icon.png)

![Stet demo](docs/assets/demo.gif)

Stet is a macOS menu bar dictation app that turns speech into usable text with minimal rewriting. It records your speech, transcribes it, and pastes the result into the current app or replaces selected text.

## Features

- Runs from the menu bar without occupying the Dock
- Starts and stops dictation with a global hotkey
- Tests microphones and lets you choose an input device
- Supports OpenAI and Groq transcription providers
- Supports `Automatic`, `Stet account`, and `Your own key` execution modes
- Supports Chinese, English, and mixed-language dictation preferences
- Includes a personal dictionary
- Updates automatically through Sparkle

## Requirements

- macOS 26.0 or later
- Apple Silicon Mac
- Xcode 26 or a compatible version when building from source
- Microphone permission
- Accessibility / Input Control permission so Stet can write text into other apps

## Getting started

Download the latest macOS release from [GitHub Releases](https://github.com/DengNaichen/Stet/releases), or build Stet from source with Xcode. On first launch, Stet guides you through permissions, dictation setup, and either a Stet account or your own API key.

To build from the repository root:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer make build
```

Open `Stet.xcodeproj` in Xcode if you want to run or debug the app directly. Let Swift Package Manager resolve dependencies, then run the `Stet` scheme.

## Development

The repository is a unified monorepo containing the macOS app, the iOS app, and shared Swift packages.

```bash
# Build the macOS app
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer make build

# Run macOS tests
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer make test

# Run SwiftLint and swift-format checks
make lint

# Build the iOS app for the simulator
make ios-build
```

See the [`Makefile`](Makefile) for all available targets. For repository conventions and the agent-facing documentation, start with [`AGENTS.md`](AGENTS.md) and [`docs/HARNESS.md`](docs/HARNESS.md).

## Repository layout

- [`StetMac/`](StetMac/) — macOS app
- [`StetMobile/`](StetMobile/) — iOS app, keyboard extension, and Live Activity
- [`Packages/StetEngine/`](Packages/StetEngine/) — shared Swift package
- [`docs/`](docs/) — architecture, specifications, release, and development documentation
- [`reference/`](reference/) — Apple platform reference material

## Privacy and runtime files

API keys, signing material, and provider credentials belong in the local Keychain or GitHub Environment secrets, never in tracked files. Model payloads, downloaded runtime frameworks, Xcode build products, and other local-only artifacts are intentionally excluded from Git.

## Release process

Official release artifacts are built by GitHub Actions. See the [release guide](docs/release.md) for the macOS release and notarization workflow.

## License

Stet is licensed under the [GNU General Public License v3.0 (GPL-3.0-only)](LICENSE).
