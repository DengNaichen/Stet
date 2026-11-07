#!/usr/bin/env python3
"""Check repository-local Markdown links offline; never edit documents."""
from __future__ import annotations

import argparse
from fnmatch import fnmatchcase
from pathlib import Path
import sys
import tomllib

# Allow direct invocation from any working directory.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from linter.common import PrerequisiteError, candidate_files, repository_root, tracked_files


def sources(root: Path, excluded: list[str]) -> list[str]:
    result = []
    for name in candidate_files(root, tracked_files(root)):
        path = root / name
        if not name.lower().endswith('.md') or any(fnmatchcase(name, p) for p in excluded):
            continue
        # Deleted tracked files are absent from the current tree. Aliases such as
        # CLAUDE.md are checked as link targets, not read as duplicate sources.
        if path.is_symlink() or not path.exists():
            continue
        result.append(name)
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parent.parent)
    args = parser.parse_args()
    try:
        from linter.markdown_checks import check_markdown
        root = repository_root(args.root)
        config = tomllib.loads((root / 'linter/config.toml').read_text())
        excluded = config['markdown']['exclude']
        if not isinstance(excluded, list) or not all(isinstance(p, str) for p in excluded):
            raise ValueError('markdown.exclude must be an array of patterns')
        diagnostics, stats = check_markdown(root, sources(root, excluded), excluded, [])
    except (ImportError, OSError, ValueError, KeyError, PrerequisiteError) as exc:
        print(f'docs-lint: setup error: {exc}; run make docs-lint-setup', file=sys.stderr)
        return 2
    for item in diagnostics:
        print(item)
    print('docs-lint: ' + ', '.join(f'{k}={v}' for k, v in stats.items())
          + f', errors={len(diagnostics)}')
    return 1 if diagnostics else 0


if __name__ == '__main__':
    raise SystemExit(main())
