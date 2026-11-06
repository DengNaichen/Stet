# Codex adapter

Repository-local OpenAI Codex lifecycle configuration. Agent routing and project
knowledge live in [`AGENTS.md`](../AGENTS.md) — not here.

## Layout

- `hooks.json` — Stop runs the architecture check on changed `StetMac/` sources;
  on new violations it blocks once and feeds back the violations together with
  the rules. Nothing is injected at session start. Codex asks to trust hooks again whenever this file changes.
- `hooks/arch.py` — hook adapter shared with Claude Code (`.claude/settings.json`);
  rules and checks live in `scripts/arch-check.py`.
- `agents/` — custom Codex subagents (placeholder)
- `environments/` — managed worktree environment setup (placeholder)

Hook commands run through `scripts/run-agent-hook`, which adds `~/.local/bin`
and `/opt/homebrew/bin` to `PATH` for desktop hosts.
