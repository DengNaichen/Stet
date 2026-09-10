import json
from dataclasses import asdict
from pathlib import Path
import unittest
from itertools import product
import subprocess
import sys

from learning import extract_replacements, GlossaryEntry, Replacement, merge_glossary


class ReplacementTests(unittest.TestCase):
    def test_portable_cases(self):
        cases = json.loads(Path(__file__).with_name("cases.json").read_text())
        for case in cases:
            with self.subTest(case=case["id"]):
                self.assertEqual(
                    [asdict(item) for item in extract_replacements(case["original"], case["edited"])],
                    case["expected"],
                )

    def test_replacement_is_independent_of_surrounding_context(self):
        # Literal corrections are the oracle; wrappers vary without changing
        # the edited words. These do not derive expected output from a diff.
        corrections = [
            ("Pyton", "Python"), ("拍图", "Python"), ("明天", "后天"),
            ("苹果", "芒果"), ("C plus plus", "C++"), ("get_usr_id", "get_user_id"),
            ("post grass", "PostgreSQL"), ("cafe", "café"),
            ("new york", "New York"), ("coffee", "tea"), ("X", "R"), ("3", "4"),
        ]
        prefixes = ["", "前文：", "Use ", "😀 ", "first\n", "(", "  ", "\t"]
        suffixes = ["", "。", " today", " 后文", " 😄", "\nend", ")", "\t"]
        for (before, after), prefix, suffix in product(corrections, prefixes, suffixes):
            with self.subTest(before=before, prefix=prefix, suffix=suffix):
                self.assertEqual(
                    extract_replacements(prefix + before + suffix, prefix + after + suffix),
                    [Replacement(before, after)],
                )

    def test_pure_insertions_and_deletions_in_repeated_sequences_are_not_learned(self):
        for size in range(1, 41):
            words = ["repeat"] * size
            for position in range(size + 1):
                original = " ".join(words)
                edited = " ".join(words[:position] + ["added"] + words[position:])
                with self.subTest(size=size, position=position):
                    self.assertEqual(extract_replacements(original, edited), [])
                    self.assertEqual(extract_replacements(edited, original), [])

    def test_resource_limits_are_explicit_errors(self):
        with self.assertRaises(ValueError):
            extract_replacements("a" * 32001, "Python")
        with self.assertRaises(ValueError):
            extract_replacements("word " * 4097, "Python")


class GlossaryTests(unittest.TestCase):
    def test_portable_glossary_cases(self):
        cases = json.loads(Path(__file__).with_name("glossary_cases.json").read_text())
        for case in cases:
            with self.subTest(case=case["id"]):
                existing = [GlossaryEntry(**e) if isinstance(e, dict) else e for e in case["existing"]]
                self.assertEqual(
                    [asdict(e) for e in merge_glossary(existing, case["terms"], source=case["source"])],
                    case["expected"],
                )

    def test_automatic_learning_preserves_manual_origin_and_migrates_legacy(self):
        self.assertEqual(
            merge_glossary(["Python"], ["python", "Swift"], source="automatic"),
            [GlossaryEntry("Python", "manual"), GlossaryEntry("Swift", "automatic")],
        )

    def test_manual_entry_takes_ownership_of_automatically_learned_word(self):
        self.assertEqual(
            merge_glossary([GlossaryEntry("python", "automatic")], ["Python"], source="manual"),
            [GlossaryEntry("Python", "manual")],
        )

    def test_invalid_source_is_rejected_even_for_an_empty_update(self):
        with self.assertRaises(ValueError):
            merge_glossary([], [], source="unknown")
        with self.assertRaises(ValueError):
            GlossaryEntry("Python", "unknown")

    def test_learning_is_idempotent_and_does_not_mutate_input(self):
        existing = ["Swift"]
        corrections = extract_replacements("Pyton and Pyton", "Python and Python")
        terms = [c.replacement for c in corrections]
        once = merge_glossary(existing, terms, source="automatic")
        self.assertEqual(merge_glossary(once, terms, source="automatic"), once)
        self.assertEqual(existing, ["Swift"])


class CommandLineTests(unittest.TestCase):
    def test_json_input_produces_replacements_and_provenance(self):
        result = subprocess.run(
            [sys.executable, str(Path(__file__).parent)],
            input=json.dumps({"original": "我用拍图", "edited": "我用Python", "glossary": ["Swift"]}),
            capture_output=True, text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), {
            "replacements": [{"original": "拍图", "replacement": "Python"}],
            "glossary": [{"term": "Swift", "source": "manual"}, {"term": "Python", "source": "automatic"}],
        })


if __name__ == "__main__":
    unittest.main()
