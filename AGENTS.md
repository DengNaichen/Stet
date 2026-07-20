# AGENTS.md

## Repository model

This is the private canonical monorepo. `Public/Stet/` is the allowlisted public
projection and `Private/StetMobile/` is private. Never copy private files into the
public subtree and never push a monorepo commit directly to the public remote.

## Entry points

- For macOS or shared public code, read `Public/Stet/AGENTS.md` and work from
  `Public/Stet/`.
- For iOS code, work from `Private/StetMobile/`. Shared sources are referenced
  from `Public/Stet/Packages/StetEngine` and `Public/Stet/StetVisuals`.
- Keep root-level changes limited to monorepo governance, CI, and orchestration.

## Build and validation

- Stable macOS build: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer make build`
- macOS tests: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer make test`
- iOS 27 simulator build: `make ios-build`; it uses Xcode Beta per-command and
  does not change the global Xcode selection.
- Formatting and lint: `make lint`
- Public boundary: `make verify-public`

Do not add model payloads or downloaded runtime frameworks to Git. Do not change
public release automation from the monorepo root; release changes belong inside
`Public/Stet/`.

Do not run Git index-writing commands in parallel. Preserve unrelated user
changes and use small, verifiable commits.
