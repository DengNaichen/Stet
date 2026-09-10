# Claude Code adapter

Repository-local Claude Code lifecycle configuration. Agent routing and project
knowledge live in [`AGENTS.md`](../AGENTS.md) and [`CLAUDE.md`](../CLAUDE.md)
(symlink) — not in Claude-only prose here.

## Files

- `settings.json.example` — template for local Claude project settings. Copy to
  `settings.json` and customize paths for your machine.
- `settings.json` — local Claude project settings (gitignored; permissions today;
  SessionStart / WorktreeRemove hooks may be added later).

Do not duplicate harness docs or reference material in this directory.
