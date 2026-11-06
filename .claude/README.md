# Claude Code adapter

Repository-local Claude Code lifecycle configuration. Agent routing and project
knowledge live in [`AGENTS.md`](../AGENTS.md) and [`CLAUDE.md`](../CLAUDE.md)
(symlink) — not in Claude-only prose here.

## Files

- `settings.json` — shared project settings (tracked). Hooks only: Stop runs the
  architecture check on changed `StetMac/` sources and, on new violations,
  feeds back the violations together with the rules. Both call `.codex/hooks/arch.py`, shared with Codex.
- `settings.local.json` — personal settings such as machine-specific permissions
  and directories (gitignored; merged over `settings.json` by Claude Code).
- `settings.json.example` — template for `settings.local.json`; copy it and
  customize paths for your machine.

Do not duplicate harness docs or reference material in this directory.
