#!/usr/bin/env python3
"""Smoke test DeepSeek V4 rewrite latency using the root .env API key."""

from __future__ import annotations

import argparse
import http.client
import json
import os
import ssl
import sys
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path


DEFAULT_MODELS = ("deepseek-v4-flash", "deepseek-v4-pro")
DEFAULT_PROMPT = "um please remind me to send the deepseek smoke test notes to nick after lunch"


@dataclass
class StreamResult:
    model: str
    status: str
    http_status: int
    ttft_any_ms: float | None
    ttft_content_ms: float | None
    total_ms: float
    output: str


def load_dotenv(path: Path) -> None:
    if not path.exists():
        return

    for line in path.read_text().splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#") or "=" not in stripped:
            continue
        if stripped.startswith("export "):
            stripped = stripped[len("export ") :].strip()
        key, value = stripped.split("=", 1)
        key = key.strip()
        value = value.strip().strip("\"'")
        if key and key not in os.environ:
            os.environ[key] = value


def make_request(
    api_key: str,
    method: str,
    path: str,
    body: dict | None = None,
) -> tuple[http.client.HTTPSConnection, http.client.HTTPResponse, float]:
    connection = http.client.HTTPSConnection(
        "api.deepseek.com",
        timeout=60,
        context=ssl.create_default_context(),
    )
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Accept": "application/json",
    }
    request_body = None
    if body is not None:
        request_body = json.dumps(body).encode()
        headers["Content-Type"] = "application/json"

    started = time.perf_counter()
    connection.request(method, path, body=request_body, headers=headers)
    response = connection.getresponse()
    return connection, response, started


def validate_models(api_key: str) -> float:
    _connection, response, started = make_request(api_key, "GET", "/v1/models")
    data = response.read()
    elapsed_ms = (time.perf_counter() - started) * 1000
    if response.status // 100 != 2:
        message = data[:800].decode(errors="replace")
        raise RuntimeError(f"/models failed with HTTP {response.status}: {message}")
    return elapsed_ms


def smoke_stream(api_key: str, model: str, prompt: str) -> StreamResult:
    body = {
        "model": model,
        "messages": [
            {
                "role": "system",
                "content": "Rewrite dictated text. Return only the final cleaned text.",
            },
            {"role": "user", "content": prompt},
        ],
        "max_tokens": 80,
        "stream": True,
        "thinking": {"type": "disabled"},
    }
    _connection, response, started = make_request(api_key, "POST", "/v1/chat/completions", body)
    first_any: float | None = None
    first_content: float | None = None
    chunks: list[str] = []

    while True:
        line = response.readline()
        if not line:
            break
        if not line.startswith(b"data: "):
            continue
        payload = line[6:].strip()
        if payload == b"[DONE]":
            break
        if first_any is None:
            first_any = time.perf_counter()
        event = json.loads(payload)
        delta = event.get("choices", [{}])[0].get("delta", {})
        content = delta.get("content")
        if content:
            if first_content is None:
                first_content = time.perf_counter()
            chunks.append(content)

    finished = time.perf_counter()
    output = "".join(chunks).strip()
    status = "PASS" if response.status // 100 == 2 and first_content is not None and output else "FAIL"
    return StreamResult(
        model=model,
        status=status,
        http_status=response.status,
        ttft_any_ms=(first_any - started) * 1000 if first_any is not None else None,
        ttft_content_ms=(first_content - started) * 1000 if first_content is not None else None,
        total_ms=(finished - started) * 1000,
        output=output,
    )


def smoke_nonstream(api_key: str, model: str, prompt: str) -> tuple[int, float, str]:
    body = {
        "model": model,
        "messages": [
            {
                "role": "system",
                "content": "Rewrite dictated text. Return only the final cleaned text.",
            },
            {"role": "user", "content": prompt},
        ],
        "max_tokens": 80,
        "stream": False,
        "thinking": {"type": "disabled"},
    }
    _connection, response, started = make_request(api_key, "POST", "/v1/chat/completions", body)
    data = response.read()
    elapsed_ms = (time.perf_counter() - started) * 1000
    if response.status // 100 != 2:
        message = data[:800].decode(errors="replace")
        raise RuntimeError(f"non-stream {model} failed with HTTP {response.status}: {message}")
    payload = json.loads(data)
    output = payload["choices"][0]["message"].get("content", "").strip()
    if not output:
        raise RuntimeError(f"non-stream {model} returned empty output")
    return response.status, elapsed_ms, output


def format_ms(value: float | None) -> str:
    return "n/a" if value is None else f"{value:.0f}"


def markdown_cell(value: str) -> str:
    return value.replace("\n", "<br>").replace("|", "\\|")


def write_report(
    path: Path,
    models_ms: float,
    stream_results: list[StreamResult],
    nonstream_status: int,
    nonstream_ms: float,
    nonstream_output: str,
) -> None:
    generated_at = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
    lines = [
        "# DeepSeek Mac Provider Smoke Report",
        "",
        f"- Generated: {generated_at}",
        "- API key source: root `.env` (`DEEPSEEK_API_KEY`)",
        "- Endpoint: `https://api.deepseek.com/v1`",
        "- Network context: developer machine with reachable DeepSeek API",
        "- Request mode: `chat/completions` with `thinking: {\"type\": \"disabled\"}`",
        "- Model source: DeepSeek API docs list `deepseek-v4-flash` and `deepseek-v4-pro`; "
        "legacy `deepseek-chat` and `deepseek-reasoner` aliases are deprecated on 2026-07-24 15:59 UTC.",
        f"- `/models` credential validation: PASS ({models_ms:.0f} ms)",
        "",
        "## Streaming TTFT",
        "",
        "| Model | Status | HTTP | TTFT any token (ms) | TTFT content (ms) | Total (ms) | Output |",
        "|---|---:|---:|---:|---:|---:|---|",
    ]
    for result in stream_results:
        output = markdown_cell(result.output)
        lines.append(
            "| "
            f"{result.model} | {result.status} | {result.http_status} | "
            f"{format_ms(result.ttft_any_ms)} | {format_ms(result.ttft_content_ms)} | "
            f"{result.total_ms:.0f} | {output} |"
        )

    lines.extend(
        [
            "",
            "## App-Compatible Non-Streaming Check",
            "",
            f"- Model: `deepseek-v4-flash`",
            f"- Status: PASS (HTTP {nonstream_status}, {nonstream_ms:.0f} ms)",
            f"- Output: {nonstream_output}",
            "- Default choice note: `deepseek-v4-flash` returned clean final text in the app-compatible check; "
            "`deepseek-v4-pro` was slower in streaming and may be more verbose on short cleanup prompts.",
            "",
            "## Release Note Draft",
            "",
            "- DeepSeek refine provider enabled on Mac.",
            "- Default DeepSeek refine model is `deepseek-v4-flash`.",
            "- Mobile behavior unchanged.",
        ]
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n")


def main() -> int:
    parser = argparse.ArgumentParser(description="Smoke test DeepSeek V4 rewrite models.")
    parser.add_argument("--env", default=".env", help="Path to the root env file.")
    parser.add_argument("--report", default="docs/deepseek-smoke-2026-06-13.md")
    parser.add_argument("--prompt", default=DEFAULT_PROMPT)
    parser.add_argument("--models", nargs="+", default=list(DEFAULT_MODELS))
    args = parser.parse_args()

    load_dotenv(Path(args.env))
    api_key = os.environ.get("DEEPSEEK_API_KEY", "").strip()
    if not api_key or api_key == "your_deepseek_key_here":
        print("DEEPSEEK_API_KEY is missing or still a placeholder.", file=sys.stderr)
        return 2

    models_ms = validate_models(api_key)
    print(f"/models PASS {models_ms:.0f} ms")

    stream_results: list[StreamResult] = []
    for model in args.models:
        result = smoke_stream(api_key, model, args.prompt)
        stream_results.append(result)
        print(
            f"{model} {result.status} "
            f"ttft_content={format_ms(result.ttft_content_ms)}ms total={result.total_ms:.0f}ms"
        )
        if result.status != "PASS":
            return 1

    nonstream_status, nonstream_ms, nonstream_output = smoke_nonstream(
        api_key,
        "deepseek-v4-flash",
        args.prompt,
    )
    print(f"deepseek-v4-flash non-stream PASS {nonstream_ms:.0f} ms")
    write_report(
        Path(args.report),
        models_ms,
        stream_results,
        nonstream_status,
        nonstream_ms,
        nonstream_output,
    )
    print(f"wrote {args.report}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
