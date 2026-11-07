# Adapted from HarnessKit shared-memory, documentation lint (0a7261f2).
"""Offline Markdown destinations and GitHub-style heading fragments.

Only supplied sources and permitted Markdown fragment targets are read. Markdown
is parsed as CommonMark with tables and strikethrough; code is never inspected as
links. Raw HTML href/src/id and anchor name attributes are supported, but HTML
heading IDs, srcset, CSS, JavaScript and non-Markdown fragments are not inferred.
"""

from __future__ import annotations

import posixpath
from dataclasses import dataclass
from fnmatch import fnmatchcase
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urlsplit

from github_slugger import GithubSlugger
from markdown_it import MarkdownIt
from markdown_it.token import Token

from .common import Diagnostic, safe_target


@dataclass(frozen=True)
class _Link:
    url: str
    line: int


@dataclass
class _Document:
    links: list[_Link]
    anchors: set[str]


class _HTMLAttributes(HTMLParser):
    """Read attributes only; never render or execute raw HTML."""

    def __init__(self, line: int):
        super().__init__(convert_charrefs=True)
        self.start_line = line
        self.links: list[_Link] = []
        self.anchors: set[str] = set()

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        for name, value in attrs:
            if value is None:
                continue
            if name in {"href", "src"}:
                self.links.append(_Link(value, self.start_line + self.getpos()[0] - 1))
            if name == "id" or (tag == "a" and name == "name"):
                self.anchors.add(value)

    def handle_startendtag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        self.handle_starttag(tag, attrs)


def _without_frontmatter(text: str) -> str:
    """Keep source line numbers while excluding an initial metadata block."""
    lines = text.splitlines(keepends=True)
    if not lines or lines[0].strip() != "---":
        return text
    for index, line in enumerate(lines[1:], 1):
        if line.strip() in {"---", "..."}:
            return "\n" * (index + 1) + "".join(lines[index + 1 :])
    return text


def _heading_text(children: list[Token]) -> str:
    # GitHub slugs use heading text, not Markdown formatting or image alt text.
    # Inline HTML tags are separate tokens; their surrounding text remains here.
    return "".join(
        child.content if child.type in {"text", "code_inline"} else " "
        for child in children
        if child.type in {"text", "code_inline", "softbreak", "hardbreak"}
    )


def _parse(text: str) -> _Document:
    parser = MarkdownIt("commonmark", {"html": True}).enable(["table", "strikethrough"])
    # Retain destinations for exact ignore matching. Accept file: links for
    # checking; no parsed destination is rendered or passed to a network client.
    parser.normalizeLink = lambda value: value
    parser.validateLink = lambda value: True
    tokens = parser.parse(_without_frontmatter(text))
    document = _Document([], set())
    slugger = GithubSlugger()

    def html(content: str, line: int) -> None:
        attributes = _HTMLAttributes(line)
        attributes.feed(content)
        attributes.close()
        document.links.extend(attributes.links)
        document.anchors.update(attributes.anchors)

    for index, token in enumerate(tokens):
        line = token.map[0] + 1 if token.map else 1
        if token.type == "heading_open":
            children = tokens[index + 1].children or []
            document.anchors.add(slugger.slug(_heading_text(children)))
        if token.type == "html_block":
            html(token.content, line)
        if token.type != "inline":
            continue
        for child in token.children or []:
            if child.type == "link_open":
                document.links.append(_Link(child.attrGet("href") or "", line))
            elif child.type == "image":
                document.links.append(_Link(child.attrGet("src") or "", line))
            elif child.type == "html_inline":
                html(child.content, line)
            if child.type in {"softbreak", "hardbreak"}:
                line += 1
            elif child.type == "html_inline":
                line += child.content.count("\n")
    return document


def _excluded(relative: str, resolved: Path, root: Path, patterns: list[str]) -> bool:
    names = {posixpath.normpath(relative), resolved.relative_to(root).as_posix()}
    return any(fnmatchcase(name, pattern) for name in names for pattern in patterns)


def _destination(root: Path, source: str, url: str) -> tuple[str, str] | None:
    """Return a repository-relative path and decoded fragment for local URLs."""
    parts = urlsplit(url)
    if parts.scheme and parts.scheme.lower() != "file":
        return None
    if parts.netloc:
        if parts.scheme.lower() == "file":
            raise ValueError("file URL authorities are not repository-local")
        return None  # A protocol-relative external URL; never fetch it.
    path = unquote(parts.path, errors="strict")
    fragment = unquote(parts.fragment, errors="strict")
    if parts.scheme.lower() == "file" and path.startswith("/"):
        try:
            relative = Path(path).relative_to(root).as_posix()
        except ValueError as exc:
            raise ValueError("file URL escapes the repository") from exc
    elif path.startswith("/"):
        relative = path.lstrip("/")
    elif path:
        relative = posixpath.join(posixpath.dirname(source), path)
    else:
        relative = source
    return relative, fragment


def check_markdown(
    root: Path,
    sources: list[str],
    excluded_targets: list[str],
    ignored_urls: list[str],
) -> tuple[list[Diagnostic], dict[str, int]]:
    """Check local links without traversing documents recursively or writing.

    Exclusions match both the destination spelling and its resolved physical
    path, so internal aliases cannot bypass excluded-body protection. Excluded
    and non-Markdown fragment targets are counted as skipped, not as validated.
    Markdown inline diagnostics use the parser's source block and line breaks;
    multiline code spans or link destinations may point at their block start.
    """
    root = root.resolve()
    diagnostics: list[Diagnostic] = []
    stats = {
        "documents_checked": 0,
        "local_links_checked": 0,
        "fragments_checked": 0,
        "fragments_skipped": 0,
        "fragments_skipped_excluded": 0,
        "fragments_skipped_non_markdown": 0,
    }
    ignored = set(ignored_urls)
    documents: dict[Path, _Document] = {}

    def read(path: Path) -> _Document:
        if path not in documents:
            documents[path] = _parse(path.read_text(encoding="utf-8"))
        return documents[path]

    for source in sorted(set(sources)):
        try:
            source_path = safe_target(root, source)
            if _excluded(source, source_path, root, excluded_targets):
                diagnostics.append(
                    Diagnostic(source, "MD_EXCLUDED_SOURCE", "excluded source body was not read")
                )
                continue
            document = read(source_path)
        except (OSError, UnicodeError, ValueError) as exc:
            diagnostics.append(Diagnostic(source, "MD_READ", str(exc)))
            continue
        stats["documents_checked"] += 1
        for link in document.links:
            if link.url in ignored:
                continue
            try:
                destination = _destination(root, source, link.url)
            except (UnicodeError, ValueError) as exc:
                diagnostics.append(Diagnostic(source, "MD_URL", f"{link.url!r}: {exc}", link.line))
                continue
            if destination is None:
                continue
            relative, fragment = destination
            stats["local_links_checked"] += 1
            try:
                target = safe_target(root, relative, allow_symlinks=True)
            except ValueError as exc:
                diagnostics.append(
                    Diagnostic(source, "MD_TARGET", f"{link.url!r}: {exc}", link.line)
                )
                continue
            if not fragment:
                continue
            if _excluded(relative, target, root, excluded_targets):
                stats["fragments_skipped"] += 1
                stats["fragments_skipped_excluded"] += 1
                continue
            if not target.is_file() or target.suffix.lower() != ".md":
                stats["fragments_skipped"] += 1
                stats["fragments_skipped_non_markdown"] += 1
                continue
            try:
                target_document = read(target)
            except (OSError, UnicodeError, ValueError) as exc:
                diagnostics.append(Diagnostic(source, "MD_READ", f"{link.url!r}: {exc}", link.line))
                continue
            stats["fragments_checked"] += 1
            if fragment not in target_document.anchors:
                diagnostics.append(
                    Diagnostic(
                        source,
                        "MD_FRAGMENT",
                        f"{link.url!r}: fragment {fragment!r} does not exist in "
                        f"{target.relative_to(root).as_posix()}",
                        link.line,
                    )
                )
    return diagnostics, stats
