# StetMobile Development

This directory contains the iOS app, keyboard extension, and Live Activity.

- Project: `StetMobile.xcodeproj` (scheme `StetMobile`).
- Build from repo root: `make ios-build` (uses Xcode Beta per-command; bootstraps ignored runtime).
- Shared package code: `../Packages/StetEngine`.
- Shared visual code: `../StetVisuals`.
- Harness entry: [`docs/HARNESS.md`](../docs/HARNESS.md).
- Run formatting and SwiftLint from the monorepo root (`make lint`).
- Keep `.runtime/`, ONNX models, downloaded frameworks, and build products out of Git.
