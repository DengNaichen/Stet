# StetMobile Development

This directory is the iOS app subtree in the unified Stet monorepo.

- Project: `StetMobile.xcodeproj` (scheme `StetMobile`).
- Build from repo root: `make ios-build` (uses Xcode Beta per-command; bootstraps ignored runtime).
- Shared package code: `../../Public/Stet/Packages/StetEngine`.
- Shared visual code: `../../Public/Stet/StetVisuals`.
- Harness entry: [`docs/HARNESS.md`](../../docs/HARNESS.md).
- Run formatting and SwiftLint from the monorepo root (`make lint`).
- Keep `.runtime/`, ONNX models, downloaded frameworks, and build products out of Git.
