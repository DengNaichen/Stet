"""Reference implementation of text-only glossary learning (Python 3.10+)."""

from dataclasses import dataclass
from difflib import SequenceMatcher
from functools import lru_cache
import unicodedata
from typing import Literal, Sequence

import jieba


@dataclass(frozen=True)
class Replacement:
    original: str
    replacement: str


Source = Literal["manual", "automatic"]


@dataclass(frozen=True)
class GlossaryEntry:
    term: str
    source: Source

    def __post_init__(self):
        if not isinstance(self.term, str):
            raise TypeError("glossary term must be a string")
        if self.source not in ("manual", "automatic"):
            raise ValueError("source must be manual or automatic")


def _clean_term(term: str) -> str:
    return " ".join(unicodedata.normalize("NFC", term).split())


def merge_glossary(
    existing: Sequence[GlossaryEntry | str], terms: Sequence[str], *, source: Source
) -> list[GlossaryEntry]:
    """Return a new glossary; legacy strings are manual, manual entries win."""
    if source not in ("manual", "automatic"):
        raise ValueError("source must be manual or automatic")
    result: dict[str, GlossaryEntry] = {}
    entries = [GlossaryEntry(e, "manual") if isinstance(e, str) else e for e in existing]
    entries += [GlossaryEntry(term, source) for term in terms]
    for entry in entries:
        term = _clean_term(entry.term)
        if not term:
            continue
        key = term.lower()
        if key not in result or (result[key].source == "automatic" and entry.source == "manual"):
            result[key] = GlossaryEntry(term, entry.source)
    return list(result.values())


@dataclass(frozen=True)
class _Token:
    text: str
    start: int
    end: int


def _is_cjk(character: str) -> bool:
    point = ord(character)
    return any(start <= point <= end for start, end in (
        (0x3400, 0x4DBF), (0x4E00, 0x9FFF), (0xF900, 0xFAFF),
        (0x20000, 0x323AF), (0x3040, 0x30FF), (0x31F0, 0x31FF),
    ))


@lru_cache(maxsize=1)
def _segmenter() -> jieba.Tokenizer:
    # Isolated vocabulary: never train on / mutate jieba's global dictionary.
    return jieba.Tokenizer()


def _word_character(character: str) -> bool:
    return not _is_cjk(character) and (
        character.isalnum() or character == "_"
        or unicodedata.category(character).startswith("M")
    )


def _tokens(text: str) -> list[_Token]:
    tokens = []
    index = 0
    while index < len(text):
        if text[index].isspace():
            index += 1
            continue
        start = index
        character = text[index]
        index += 1
        if character.isalnum() and _is_cjk(character):
            while index < len(text) and text[index].isalnum() and _is_cjk(text[index]):
                index += 1
            for word, begin, end in _segmenter().tokenize(text[start:index], HMM=False):
                tokens.append(_Token(word, start + begin, start + end))
            continue
        word_start = _word_character(character)
        if character in ".@#" and index < len(text) and _word_character(text[index]):
            word_start = start == 0 or not text[start - 1].isalnum() or _is_cjk(text[start - 1])
        if word_start:
            while index < len(text):
                current = text[index]
                if _word_character(current):
                    index += 1
                elif current in ".-'’/" and index + 1 < len(text) and _word_character(text[index + 1]):
                    index += 1
                elif current in "+#":
                    index += 1
                else:
                    break
        tokens.append(_Token(text[start:index], start, index))
    return tokens


def extract_replacements(original: str, edited: str) -> list[Replacement]:
    if not isinstance(original, str) or not isinstance(edited, str):
        raise TypeError("original and edited must be strings")
    if max(len(original), len(edited)) > 32000:
        raise ValueError("text exceeds 32000 Unicode code points")
    original = unicodedata.normalize("NFC", original)
    edited = unicodedata.normalize("NFC", edited)
    old = _tokens(original)
    new = _tokens(edited)
    if max(len(old), len(new)) > 4096:
        raise ValueError("text exceeds 4096 tokens")
    # Pin unchanged edges before the longest-match heuristic: otherwise the
    # first edit in "foo foo" → "bar foo" can look like an insertion/deletion.
    prefix = 0
    while prefix < min(len(old), len(new)) and old[prefix].text == new[prefix].text:
        prefix += 1
    old_end, new_end = len(old), len(new)
    while old_end > prefix and new_end > prefix and old[old_end - 1].text == new[new_end - 1].text:
        old_end -= 1
        new_end -= 1
    old = old[prefix:old_end]
    new = new[prefix:new_end]
    matcher = SequenceMatcher(None, [t.text.lower() for t in old], [t.text.lower() for t in new], autojunk=False)
    changed_ranges = []
    for operation, i, j, k, l in matcher.get_opcodes():
        if operation == "replace":
            changed_ranges.append((i, j, k, l))
        elif operation == "equal":
            # A case-only edit is still a replacement, but must not absorb a
            # following pure insertion ("react" → "React every day").
            start = None
            for offset in range(j - i + 1):
                changed = offset < j - i and old[i + offset].text != new[k + offset].text
                if changed and start is None:
                    start = offset
                if not changed and start is not None:
                    changed_ranges.append((i + start, i + offset, k + start, k + offset))
                    start = None
    replacements = []
    for i, j, k, l in changed_ranges:
        old_words = [t for t in old[i:j] if any(c.isalnum() for c in t.text)]
        new_words = [t for t in new[k:l] if any(c.isalnum() for c in t.text)]
        if old_words and new_words:
            replacements.append(Replacement(
                original[old_words[0].start:old_words[-1].end],
                edited[new_words[0].start:new_words[-1].end],
            ))
    return replacements
