# Codex adapter

Repository-local OpenAI Codex lifecycle configuration. Agent routing and project
knowledge live in [`AGENTS.md`](../AGENTS.md) — not here.

Commits do not require generating or refreshing `HANDOFF.md`.

## Layout

- `hooks.json` — SessionStart prepares cached tools in the current checkout; Stop runs the architecture check on changed `StetMac/` sources;
  on new violations it blocks once and feeds back the violations together with
  the rules. Codex asks to trust hooks again whenever this file changes.
- `hooks/arch.py` — hook adapter shared with Claude Code (`.claude/settings.json`);
  rules and checks live in `scripts/arch-check.py`.
- `agents/` — custom Codex subagents (placeholder)
- `environments/environment.toml` — Darwin worktree creation calls the shared setup entrypoint.

Hook commands run through `scripts/run-agent-hook`, which adds `~/.local/bin`
and `/opt/homebrew/bin` to `PATH` for desktop hosts.

Cache behavior and validation: [worktrees](../docs/worktrees.md).
