# GitHub Actions

## Active workflows (repository root)

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `monorepo-ci.yml` | PR + push to `main`, `migration/**` | Swift lint/format, macOS build, macOS tests |
| `macos-release.yml` | Tags `v*` + manual | Signed macOS release (runs at repository root) |
| `macos-release-candidate.yml` | Manual | Release candidate build (runs at repository root) |

Release jobs run at the repository root, where the scripts and Xcode project now live.
