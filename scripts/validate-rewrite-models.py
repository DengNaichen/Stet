#!/usr/bin/env python3
"""Validate the remote rewrite model catalog and require revision bumps."""
import argparse
import json
from pathlib import Path
import re
import subprocess

CONFIG = "StetMac/Resources/rewrite-models.json"
PROVIDERS = {"openai", "google", "anthropic", "groq", "deepseek", "qwen", "glm", "doubao"}
ID = re.compile(r"[A-Za-z0-9][A-Za-z0-9._/-]{0,254}")
THINKING_LEVELS = {"off", "minimal", "low", "medium", "high", "max"}


def validate(raw):
    if len(raw) > 262_144:
        raise ValueError("Configuration exceeds 256 KiB")
    value = json.loads(raw)
    if type(value.get("schemaVersion")) is not int or value["schemaVersion"] != 1:
        raise ValueError("schemaVersion must be 1")
    if type(value.get("revision")) is not int or value["revision"] < 1:
        raise ValueError("revision must be a positive integer")
    providers = value.get("providers")
    if not isinstance(providers, list) or len(providers) > 32:
        raise ValueError("providers must be an array with at most 32 entries")
    provider_ids = [provider.get("id") for provider in providers if isinstance(provider, dict)]
    if len(provider_ids) != len(providers) or len(set(provider_ids)) != len(provider_ids):
        raise ValueError("Provider entries must be objects with unique IDs")
    for provider in providers:
        if provider.get("id") not in PROVIDERS or type(provider.get("enabled")) is not bool:
            raise ValueError("Unknown provider or invalid enabled value")
        models = provider.get("models")
        if not isinstance(models, list) or len(models) > 100:
            raise ValueError("models must be an array with at most 100 entries")
        model_ids = []
        for model in models:
            if not isinstance(model, dict) or type(model.get("enabled")) is not bool:
                raise ValueError("Invalid model entry")
            model_id, name = model.get("id"), model.get("displayName")
            if not isinstance(model_id, str) or not ID.fullmatch(model_id):
                raise ValueError("Invalid model ID")
            if not isinstance(name, str) or not name.strip() or len(name) > 100:
                raise ValueError("Invalid model display name")
            levels = model.get("thinkingLevels")
            default_level = model.get("defaultThinkingLevel")
            if levels is not None:
                if (not isinstance(levels, list) or not levels or len(levels) > len(THINKING_LEVELS)
                        or len(set(levels)) != len(levels)
                        or not all(isinstance(level, str) and level in THINKING_LEVELS for level in levels)):
                    raise ValueError("Invalid thinkingLevels")
                if default_level not in levels:
                    raise ValueError("defaultThinkingLevel must reference a supported thinking level")
            elif default_level is not None:
                raise ValueError("defaultThinkingLevel requires thinkingLevels")
            model_ids.append(model_id)
        if len(set(model_ids)) != len(model_ids):
            raise ValueError("Duplicate model IDs within provider")
        default_id = provider.get("defaultModelID")
        if not any(model["id"] == default_id and model["enabled"] for model in models):
            raise ValueError("defaultModelID must reference an enabled model")
    return value


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-ref")
    args = parser.parse_args()
    current = validate(Path(CONFIG).read_bytes())
    if args.base_ref:
        previous = subprocess.run(
            ["git", "show", f"{args.base_ref}:{CONFIG}"], capture_output=True, check=False)
        if previous.returncode == 0:
            old = validate(previous.stdout)
            if current != old and current["revision"] <= old["revision"]:
                raise ValueError("Increment revision whenever the rewrite model catalog changes")
    count = sum(len(provider["models"]) for provider in current["providers"])
    print(f"Rewrite model revision {current['revision']}: {count} valid models")


if __name__ == "__main__":
    main()
