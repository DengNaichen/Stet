"""Read one JSON request from stdin; print a result without changing any files."""

from dataclasses import asdict
import json
import sys

from learning import GlossaryEntry, extract_replacements, merge_glossary


def main() -> int:
    try:
        raw = sys.stdin.read(1_000_001)
        if len(raw) > 1_000_000:
            raise ValueError("request exceeds 1000000 characters")
        payload = json.loads(raw)
        if not isinstance(payload, dict):
            raise ValueError("request must be a JSON object")
        original, edited = payload["original"], payload["edited"]
        glossary = payload.get("glossary", [])
        if not isinstance(glossary, list):
            raise ValueError("glossary must be a list")
        existing = [
            GlossaryEntry(**entry) if isinstance(entry, dict) else entry
            for entry in glossary
        ]
        if not all(isinstance(entry, (str, GlossaryEntry)) for entry in existing):
            raise ValueError("glossary entries must be strings or term/source objects")
        replacements = extract_replacements(original, edited)
        updated = merge_glossary(existing, [r.replacement for r in replacements], source="automatic")
        print(json.dumps({
            "replacements": [asdict(r) for r in replacements],
            "glossary": [asdict(e) for e in updated],
        }, ensure_ascii=False, indent=2))
        return 0
    except (ValueError, TypeError, KeyError) as error:
        print(json.dumps({"error": str(error)}, ensure_ascii=False), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
