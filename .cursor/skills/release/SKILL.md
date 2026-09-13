---
name: release
description: Run the Stet macOS release workflow from the latest main branch, including version bumping, tag creation, remote verification, and GitHub Actions follow-up. Use when the user asks to publish a release, bump the app version, create a release tag, or start the macOS release workflow.
---

# Stet Release

Use this workflow for a formal macOS release. Formal release artifacts are built and published by GitHub Actions; do not build or upload them locally.

## Release checklist

1. Confirm the requested semantic version `X.Y.Z` and use tag `vX.Y.Z`.
2. Confirm the target PRs are merged into `main` and the working tree has no unrelated changes.
3. Fetch the latest `main` and tags:

   ```bash
   git fetch origin main
   git fetch origin tag vX.Y.Z 2>/dev/null || true
   ```

4. Check that local `main` is the intended release base and is fast-forwarded to `origin/main`:

   ```bash
   git switch main
   git merge --ff-only origin/main
   git status --short
   ```

   Stop if the tree is dirty or the branch cannot be fast-forwarded.

5. Check that `vX.Y.Z` does not already exist locally or on `origin`.
6. Run the repository release script from the repository root:

   ```bash
   ./scripts/bump-version.sh X.Y.Z
   ```

   The script updates `Stet.xcodeproj/project.pbxproj`, calculates `CURRENT_PROJECT_VERSION` as `major * 1_000_000 + minor * 1_000 + patch`, commits the change, and pushes `main` and `vX.Y.Z`.

7. Verify the published refs point to the version commit:

   ```bash
   git fetch origin main
   git rev-parse origin/main
   git rev-parse origin/vX.Y.Z^{commit}
   git ls-remote origin refs/heads/main refs/tags/vX.Y.Z
   ```

8. Confirm the `macOS Release` workflow was triggered by `vX.Y.Z` and report its GitHub Actions URL. The workflow builds, signs, notarizes, generates the Sparkle appcast, creates the GitHub Release, and uploads the release artifacts.

## Release candidate

For a candidate, use the `macOS Release Candidate` workflow through `workflow_dispatch` with a tag such as `vX.Y.Z-rc1`. Keep it separate from the formal release tag and confirm the artifact upload succeeds before making the formal release.

## Stop conditions

Stop and ask for clarification if the version is ambiguous, the requested tag already exists, `main` is not current, the working tree is dirty, or a release workflow fails. Do not force-push `main` or overwrite an existing tag.
