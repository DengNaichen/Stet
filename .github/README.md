# GitHub Actions

## Active workflows (repository root)

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `monorepo-ci.yml` | PR + push to `main`, `migration/**` | Swift lint/format, macOS build, macOS tests |
| `macos-release.yml` | Tags `v*` + manual | Signed macOS release (runs in `Public/Stet/`) |
| `macos-release-candidate.yml` | Manual | Release candidate build (runs in `Public/Stet/`) |

Release jobs use `working-directory: Public/Stet` because scripts and Xcode project paths
live under that subtree.

## Legacy copies under `Public/Stet/.github/workflows/`

Kept as reference during the unified-repo migration. GitHub only executes workflows from
the repository root `.github/workflows/` directory.
