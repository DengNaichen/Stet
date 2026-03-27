# Release Guide

This document records the release flow that is currently working for Stet.

## Overview

Stet now uses three GitHub Actions workflows:

- `macOS CI`
  - file: `.github/workflows/macos-ci.yml`
  - trigger: pull requests and normal CI pushes
  - purpose: lint, build, test

- `macOS Release Candidate`
  - file: `.github/workflows/macos-release-candidate.yml`
  - trigger: `workflow_dispatch`
  - environment: `release-candidate`
  - purpose: build a signed and notarized release candidate artifact without publishing a GitHub Release

- `macOS Release`
  - file: `.github/workflows/macos-release.yml`
  - trigger: `push` on `v*` tags, plus `workflow_dispatch` for safe manual testing
  - environment: `production`
  - purpose: build, sign, notarize, generate Sparkle appcast, publish GitHub Release, upload assets

## Daily Release Flow

Normal development:

1. Open a branch and submit a PR.
2. Let `macOS CI` pass.
3. Merge into `main`.

Release validation:

1. If needed, run `macOS Release Candidate` manually from GitHub Actions.
2. Use a test label such as `v0.0.10-rc1`.
3. Confirm signing, notarization, DMG generation, and artifact upload all succeed.

Formal release:

1. Update app version and build number in the project.
2. Ensure `main` contains the release commit.
3. Push a tag such as `v0.0.10`.
4. GitHub Actions runs `macOS Release`.
5. The workflow publishes the DMG and `appcast.xml` to GitHub Releases.

## GitHub Environments

### `release-candidate`

Secrets:

- `APPLE_ID`
- `APPLE_TEAM_ID`
- `APP_SPECIFIC_PASSWORD`
- `DEVELOPER_ID_APPLICATION_P12_BASE64`
- `DEVELOPER_ID_APPLICATION_P12_PASSWORD`

Variables:

- `DEVELOPER_ID_APPLICATION`
- `ARCHIVE_PROVISIONING_PROFILE_SPECIFIER` if the release archive needs a distribution provisioning profile

### `production`

Secrets:

- `APPLE_ID`
- `APPLE_TEAM_ID`
- `APP_SPECIFIC_PASSWORD`
- `DEVELOPER_ID_APPLICATION_P12_BASE64`
- `DEVELOPER_ID_APPLICATION_P12_PASSWORD`
- `SPARKLE_PRIVATE_KEY_BASE64`

Variables:

- `DEVELOPER_ID_APPLICATION`
- `ARCHIVE_PROVISIONING_PROFILE_SPECIFIER` if required
- `SPARKLE_APPCAST_URL`
- `SPARKLE_PUBLIC_ED_KEY`
- `SPARKLE_FEED_BASE_URL`

## Important Sparkle Note

The most error-prone value is:

- `SPARKLE_PRIVATE_KEY_BASE64`

This secret must not be copied manually from the Keychain UI.

The correct value is the exported file produced by Sparkle's `generate_keys -x`, or an equivalent file that contains the exact exported Sparkle secret.

Correct pattern:

1. Build Sparkle's `generate_keys` tool.
2. Export the key:

```bash
generate_keys -x /tmp/private-key.txt
```

3. Put the contents of `/tmp/private-key.txt` directly into GitHub `production` secret `SPARKLE_PRIVATE_KEY_BASE64`.

Notes:

- The exported file is already the base64 text Sparkle expects.
- Do not decode it before storing it in GitHub.
- Do not use the raw password text copied from Keychain Access as a replacement.

## Current Workflow Behavior

### Release candidate

`macOS Release Candidate` does all of the following:

- imports the Developer ID certificate into a temporary keychain
- stores `notarytool` credentials
- runs `scripts/release-macos-github.sh`
- uploads `dist/github-release/<release_tag>/` as an artifact

Sparkle appcast generation is intentionally disabled there.

### Production release

`macOS Release` additionally does the following:

- resolves release metadata for draft/prerelease or formal tag mode
- materializes the Sparkle secret into a temporary file
- downloads Sparkle source matching `Package.resolved`
- builds `generate_appcast` in CI
- runs `scripts/release-macos-github.sh`
- runs `scripts/publish-github-release.sh`

The manual `workflow_dispatch` path is safe for testing because it sets:

- draft release = `true`
- prerelease = `true`
- latest = `false`
- verify tag = `false`

## Known Notes

- `spctl` may report `source=Insufficient Context` for the DMG inside CI. The workflow treats stapler validation as the stronger signal.
- The release workflow currently builds Sparkle's `generate_appcast` from source because Sparkle's SwiftPM package only provides the framework binary target, not the CLI tool.
- For manual release tests, artifact upload uses the provided `release_tag`, not `github.ref_name`.

