# Open-source export automation

You now have two scripts:

- `./scripts/export-open-source.sh /path/to/export-dir`
- `./scripts/sync-open-source-export.sh`

## Recommended setup

1. Keep this repository as your main development checkout.
2. Create a second checkout for the public repository.
3. Export and sync from the main repo into the public repo checkout.

If you also split topic branches into separate worktrees for investigation,
keep those worktrees around for later analysis. For example, this repo may keep
`feature/openclaw-integration` and `feature/text-output-handling-spec` in their
own worktrees so they can be studied independently even when they no longer
merge cleanly into `main`.

Example:

```bash
export PUBLIC_REPO_DIR="$HOME/Developer/stet-open"
./scripts/sync-open-source-export.sh
```

That script will:

- detect whether watched backend/open-source files changed
- generate a sanitized export
- copy it into the public repo checkout
- commit the changes there
- push the public repo by default

## Automatic sync on push

If you want this to run whenever you push the main repo:

```bash
./scripts/install-open-source-pre-push-hook.sh
export PUBLIC_REPO_DIR="$HOME/Developer/stet-open"
```

Then a normal `git push` from the main repo will first run the export sync.

## Useful environment variables

- `PUBLIC_REPO_DIR`
- `PUBLIC_REPO_BRANCH` default: `main`
- `PUBLIC_REPO_REMOTE` default: `origin`
- `OPEN_SOURCE_SYNC_PUSH` default: `true`
- `OPEN_SOURCE_SYNC_BASE_REF` optional explicit diff base
- `OPEN_SOURCE_COMMIT_MESSAGE` optional custom commit message

## Notes

- The hook uses `pre-push`, because Git does not provide a built-in `post-push` hook.
- If the export sync fails, the main repo push will be blocked. That is intentional.
- If you want a softer workflow, run `./scripts/sync-open-source-export.sh` manually instead of installing the hook.
