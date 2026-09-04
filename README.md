# Stet

The public canonical monorepo for Stet — macOS dictation app, iOS app, shared
Swift packages, and agent harness docs in one repository.

## Layout

- `Public/Stet/` — macOS app (`Stet.xcodeproj`, `StetMac/`, `StetVisuals/`, release scripts)
- `Private/StetMobile/` — iOS app (`StetMobile.xcodeproj`, keyboard extension, Live Activity)
- `Public/Stet/Packages/` — shared Swift packages (`StetEngine`, etc.)
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

For macOS-only targets (release, doctor, etc.), see [`Public/Stet/Makefile`](Public/Stet/Makefile) and [`Public/Stet/README.md`](Public/Stet/README.md).

## Agent entry

Start with [`AGENTS.md`](AGENTS.md) and [`docs/HARNESS.md`](docs/HARNESS.md).

## Visibility

The full repository — including `Private/StetMobile/` — is intended to be
public. The `Private/` directory name is historical layout, not an access-control
boundary. API keys, signing material, and provider credentials belong in GitHub
Environment secrets or local Keychain, never in tracked files.

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
See [`Public/Stet/README.md`](Public/Stet/README.md) for macOS-specific notes.
