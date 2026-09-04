# Stet v0.2.10 Release Notes

## User-Facing Changes

- DeepSeek is now available as a Mac transcript improvement provider.
- The default DeepSeek refine model is `deepseek-v4-flash`.
- `deepseek-v4-pro` is available as an alternate DeepSeek refine model.
- Mobile behavior is unchanged.

## Validation

- DeepSeek `/models` credential validation passed from the developer machine.
- Streaming smoke tests passed for `deepseek-v4-flash` and `deepseek-v4-pro`.
- App-compatible non-streaming rewrite smoke passed for `deepseek-v4-flash`.
- Detailed smoke results are recorded in `docs/deepseek-smoke-2026-06-13.md`.
