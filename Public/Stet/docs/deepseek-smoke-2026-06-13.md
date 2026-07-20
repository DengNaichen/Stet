# DeepSeek Mac Provider Smoke Report

- Generated: 2026-06-13 08:57:05 UTC
- API key source: root `.env` (`DEEPSEEK_API_KEY`)
- Endpoint: `https://api.deepseek.com/v1`
- Network context: developer machine with reachable DeepSeek API
- Request mode: `chat/completions` with `thinking: {"type": "disabled"}`
- Model source: DeepSeek API docs list `deepseek-v4-flash` and `deepseek-v4-pro`; legacy `deepseek-chat` and `deepseek-reasoner` aliases are deprecated on 2026-07-24 15:59 UTC.
- `/models` credential validation: PASS (1075 ms)

## Streaming TTFT

| Model | Status | HTTP | TTFT any token (ms) | TTFT content (ms) | Total (ms) | Output |
|---|---:|---:|---:|---:|---:|---|
| deepseek-v4-flash | PASS | 200 | 158 | 509 | 729 | Please remind me to send the DeepSeek smoke test notes to Nick after lunch. |
| deepseek-v4-pro | PASS | 200 | 165 | 644 | 968 | Sure! Here's a cleaned-up version of your text:<br><br>"Um, please remind me to send the DeepSeek smoke test notes to Nick after lunch." |

## App-Compatible Non-Streaming Check

- Model: `deepseek-v4-flash`
- Status: PASS (HTTP 200, 1084 ms)
- Output: Please remind me to send the DeepSeek smoke test notes to Nick after lunch.
- Default choice note: `deepseek-v4-flash` returned clean final text in the app-compatible check; `deepseek-v4-pro` was slower in streaming and may be more verbose on short cleanup prompts.

## Release Note Draft

- DeepSeek refine provider enabled on Mac.
- Default DeepSeek refine model is `deepseek-v4-flash`.
- Mobile behavior unchanged.
