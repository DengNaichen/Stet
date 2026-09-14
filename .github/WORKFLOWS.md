# GitHub Actions

## Active workflows (repository root)

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `monorepo-ci.yml` | PR + push to `main`, `migration/**` | Linux repository checks, affected Swift lint/format and macOS build/tests, aggregate result |
| `macos-release.yml` | Tags `v*` + manual | Signed macOS release (runs at repository root) |
| `macos-release-candidate.yml` | Manual | Release candidate build (runs at repository root) |

Release jobs run at the repository root, where the scripts and Xcode project now live.

macOS CI cache design, measured baseline, and cold/warm validation results: [CI performance](ci-performance.md).

## Change-based CI scope

Every event starts `Repository Checks` on Linux. It computes the complete Git
diff with `scripts/ci-changes.py`, validates the compatibility list and revision,
runs the CI helper regression tests, and checks harness entrypoints. Workflow
changes also run actionlint 1.7.12. No workflow-level path filters are used.

| Changed files | Additional jobs |
| --- | --- |
| `StetMac/Resources/app-compatibility.json`, root/docs/reference Markdown, agent docs | None |
| macOS Swift files in `StetMac`, `StetMacTests`, `StetMacUITests`, `StetVisuals` | Swift Quality + macOS Tests |
| macOS resources, Metal, entitlements, `Info.plist`, Xcode project, shared packages | macOS Tests |
| iOS Swift files in the existing lint directories | Swift Quality |
| Other iOS-only files | None; simulator builds remain local |
| `.swiftlint.yml`, `.swift-format` | Swift Quality |
| `Makefile`, main CI workflow, routing helper or its tests | Swift Quality + macOS Tests + actionlint |
| Other workflows | actionlint on Linux |
| Unclassified paths | Swift Quality + macOS Tests (conservative fallback) |

Mixed changes run the union of affected jobs. Markdown inside macOS app/resource
directories is conservatively treated as a build input. Shared packages keep
their existing build/test coverage; this change does not expand the directories
covered by `make lint` or add an iOS hosted build.

`macOS Tests` runs `make test`, which builds the Debug app and dependencies before
executing the full existing StetTests suite with coverage. The redundant standalone
Debug build job is removed. Test cache keys remain compatible with the previous
matrix's `test` entry. Release/RC builds are unchanged.

PR routing uses the merge-base-to-head diff across all commits; builds still use
GitHub's merged checkout. Compatibility revision validation uses the current PR
base SHA. Pushes compare `before` to `after`, including all commits in the push;
new branches inspect the full tree. Deleted and renamed paths are included, with
no 300-file limit. Missing Git history fails the check rather than skipping jobs.
PR and post-merge push checks both remain enabled to validate integration; both
use the same routing, so a list-only merge never needs a macOS runner.

`CI Result` always runs and requires repository checks plus every selected job to
succeed. Intentionally unselected jobs must report `skipped`; missing outputs,
failures, and cancellations fail the gate. Use **CI Result** as the required
branch-protection check if protection is enabled; remove the retired **macOS
Build** requirement. This workflow change does not edit repository protection.

Local verification: `python3 -m unittest discover -s scripts/tests -p 'test_*.py'`,
`python3 scripts/validate-app-compatibility.py --base-ref origin/main`,
`scripts/validate-agent-entrypoints`, and `actionlint`.
