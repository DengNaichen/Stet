# Stet

The open-source repository for Stet — macOS and iOS dictation apps, shared
Swift packages, and agent harness docs in one repository. All source is public;
the former `Public/` and `Private/` wrappers have been removed.

## Layout

- `Stet.xcodeproj`, `StetMac/`, `StetMacTests/`, `StetMacUITests/`, and `StetVisuals/` — macOS app and tests
- `StetMobile/` — iOS app, keyboard extension, Live Activity, and tests
- `Packages/StetEngine/` — shared Swift package
- `docs/` — harness docs (architecture, specs, exec-plans, validation)
- `reference/` — Apple platform reference library (read on demand)
- Root `Makefile` — orchestrates build, test, lint, and iOS simulator build across subtrees

## Common commands

From the repository root:

```bash
make build          # macOS app
make test           # macOS tests
make ios-build      # iOS simulator build (bootstraps ignored runtime)
make lint           # SwiftLint and swift-format across macOS and iOS sources
```

For macOS-only targets (release, doctor, etc.), see [`Makefile`](Makefile) and [`docs/release.md`](docs/release.md).

## Agent entry

Start with [`AGENTS.md`](AGENTS.md) and [`docs/HARNESS.md`](docs/HARNESS.md).

## Visibility

The full repository is public. API keys, signing material, and provider
credentials belong in GitHub Environment secrets or local Keychain, never in
tracked files.

## Runtime policy

Model payloads, downloaded iOS runtime frameworks, Xcode build products, and
local-only checkouts are not tracked in Git. Ignore rules live in the repository
root [`.gitignore`](.gitignore) only (no per-subtree copies).

## Git remotes

Canonical remote (releases, stars, CI secrets): **`origin`** → `github.com/DengNaichen/Stet`

Legacy development mirror: **`stet-internal`** → `github.com/DengNaichen/Stet-internal`

After the unified-monorepo migration, push to `origin` only. Prune stale
remote-tracking branches with `git remote prune origin` (and `stet-internal` if
kept).

## License

Stet is licensed under [GNU General Public License v3.0 (GPL-3.0-only)](LICENSE).
See [`docs/release.md`](docs/release.md) for macOS-specific release notes.
