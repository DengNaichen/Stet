"""Integration tests against real Markdown parsing and a temporary filesystem."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from linter.markdown_checks import check_markdown


class MarkdownChecksTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()

    def write(self, name: str, text: str = "") -> Path:
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        return path

    def check(self, sources=None, excluded=None, ignored=None):
        return check_markdown(self.root, sources or ["README.md"], excluded or [], ignored or [])

    def test_reference_links_images_queries_and_encoded_destinations(self) -> None:
        self.write(
            "README.md",
            "[文档][guide]\n![图][image]\n[目录](docs/)\n"
            "[根路径](/docs/guide%20one.md?raw=1#%E4%B8%AD%E6%96%87)\n\n"
            "[guide]: docs/guide%20one.md#中文\n[image]: assets/a%20b.png\n",
        )
        self.write("docs/guide one.md", "# 中文\n")
        self.write("assets/a b.png")
        diagnostics, stats = self.check()
        self.assertEqual(diagnostics, [])
        self.assertEqual(stats["local_links_checked"], 4)
        self.assertEqual(stats["fragments_checked"], 2)

    def test_all_heading_levels_duplicates_and_rendered_heading_text(self) -> None:
        self.write(
            "README.md",
            "# 同名\n## 同名\n### 同名\n#### 同名\n##### 同名\n###### 同名\n"
            "# 中文 `代码` & 标点：你好！\n# *Bold* <em>HTML</em> &amp; text\n"
            + "\n".join(f"[标题](#同名{suffix})" for suffix in ["", "-1", "-2", "-3", "-4", "-5"])
            + "\n[中文](#中文-代码--标点你好)\n[纯文本](#bold-html--text)\n",
        )
        diagnostics, stats = self.check()
        self.assertEqual(diagnostics, [])
        self.assertEqual(stats["fragments_checked"], 8)

    def test_setext_and_collision_order(self) -> None:
        self.write(
            "README.md",
            "Same\n====\n# Same-1\n## Same\n[one](#same) [two](#same-1) [three](#same-2)\n",
        )
        self.assertEqual(self.check()[0], [])

    def test_code_metadata_and_external_urls_are_not_local_links(self) -> None:
        self.write(
            "README.md",
            "---\nexample: '[metadata](missing.md)'\n---\n"
            "`[inline](missing.md)`\n\n```md\n[fenced](missing.md)\n"
            '<a href="missing.md">example</a>\n```\n\n'
            "    [indented](missing.md)\n\n"
            "[web](https://example.invalid/a.md#no) [mail](mailto:x@example.invalid)\n"
            "![remote](//example.invalid/a.png)\n",
        )
        # Any attempted network access is a failure even for external links.
        with patch("socket.socket", side_effect=AssertionError("network is forbidden")):
            diagnostics, stats = self.check()
        self.assertEqual(diagnostics, [])
        self.assertEqual(stats["local_links_checked"], 0)

    def test_missing_file_fragment_and_image_report_source(self) -> None:
        self.write(
            "README.md", "# Title\n\n[missing](missing.md)\n[bad](#absent)\n![img](missing.png)\n"
        )
        diagnostics, _ = self.check()
        self.assertEqual(
            [item.code for item in diagnostics], ["MD_TARGET", "MD_FRAGMENT", "MD_TARGET"]
        )
        self.assertEqual([item.line for item in diagnostics], [3, 4, 5])
        self.assertTrue(all(item.path == "README.md" for item in diagnostics))

    def test_html_attributes_and_custom_anchors(self) -> None:
        self.write(
            "README.md",
            '<a id="custom" href="docs/other.md#target">x</a>\n'
            '<img src="assets/a.png" />\n<a name="legacy"></a>\n'
            "[id](#custom) [name](#legacy)\n",
        )
        self.write("docs/other.md", '<div id="target"></div>\n')
        self.write("assets/a.png")
        diagnostics, stats = self.check()
        self.assertEqual(diagnostics, [])
        self.assertEqual(stats["fragments_checked"], 3)

    def test_excluded_targets_and_aliases_are_not_read(self) -> None:
        self.write(
            "README.md",
            "[ADR](docs/adr/old.md#never-read)\n"
            "[alias](alias.md#never-read)\n[non-markdown](data.txt#anything)\n",
        )
        historical = self.write("docs/adr/old.md", "unread historical content")
        (self.root / "alias.md").symlink_to("docs/adr/old.md")
        non_markdown = self.write("data.txt", "unread data")
        original_read = Path.read_text
        reads = []

        def guarded_read(path, *args, **kwargs):
            self.assertNotIn(path.resolve(), {historical, non_markdown})
            reads.append(path)
            return original_read(path, *args, **kwargs)

        with patch.object(Path, "read_text", guarded_read):
            diagnostics, stats = self.check(excluded=["docs/adr/**"])
        self.assertEqual(diagnostics, [])
        self.assertEqual(reads, [self.root / "README.md"])
        self.assertEqual(stats["fragments_checked"], 0)
        self.assertEqual(stats["fragments_skipped"], 3)
        self.assertEqual(stats["fragments_skipped_excluded"], 2)
        self.assertEqual(stats["fragments_skipped_non_markdown"], 1)

    def test_safe_internal_alias_and_symlink_escape(self) -> None:
        self.write("README.md", "[internal](alias.md#okay)\n[outside](outside.md#no)\n")
        self.write("docs/target.md", "# Okay\n")
        (self.root / "alias.md").symlink_to("docs/target.md")
        with tempfile.TemporaryDirectory() as outside:
            external = Path(outside) / "external.md"
            external.write_text("# No\n", encoding="utf-8")
            (self.root / "outside.md").symlink_to(external)
            diagnostics, stats = self.check()
        self.assertEqual([item.code for item in diagnostics], ["MD_TARGET"])
        self.assertIn("escapes", diagnostics[0].message)
        self.assertEqual(stats["fragments_checked"], 1)

    def test_case_sensitive_paths_and_traversal(self) -> None:
        self.write("README.md", "[case](docs/guide.md)\n[escape](%2e%2e/outside.md)\n")
        self.write("docs/Guide.md")
        diagnostics, _ = self.check()
        self.assertEqual([item.code for item in diagnostics], ["MD_TARGET", "MD_TARGET"])
        self.assertIn("case mismatch", diagnostics[0].message)
        self.assertIn("escapes", diagnostics[1].message)

    def test_file_urls_stay_inside_repository(self) -> None:
        target = self.write("docs/file.md", "# Heading\n")
        self.write(
            "README.md",
            f"[absolute]({target.as_uri()}#heading)\n[relative](file:docs/file.md#heading)\n"
            "[external](file:///tmp/outside.md)\n[host](file://host/doc.md)\n",
        )
        diagnostics, stats = self.check()
        self.assertEqual([item.code for item in diagnostics], ["MD_URL", "MD_URL"])
        self.assertEqual(stats["fragments_checked"], 2)

    def test_ignored_urls_are_exact_and_targets_are_not_checked_recursively(self) -> None:
        self.write(
            "README.md",
            "[route](/docs/getting-started)\n[not-ignored](/docs/getting-started/extra)\n"
            "[target](target.md#present)\n",
        )
        self.write("target.md", "# Present\n[not-a-source](missing.md)\n")
        diagnostics, stats = self.check(ignored=["/docs/getting-started"])
        self.assertEqual([item.code for item in diagnostics], ["MD_TARGET"])
        self.assertIn("/extra", diagnostics[0].message)
        self.assertEqual(stats["documents_checked"], 1)

    def test_excluded_source_defense_and_source_symlinks(self) -> None:
        self.write("docs/adr/old.md", "# Never read\n")
        self.write("target.md", "# Target\n")
        (self.root / "alias.md").symlink_to("target.md")
        with patch.object(Path, "read_text", side_effect=AssertionError("must not read")):
            diagnostics, stats = self.check(
                sources=["docs/adr/old.md", "alias.md"], excluded=["docs/adr/**"]
            )
        self.assertEqual([item.code for item in diagnostics], ["MD_READ", "MD_EXCLUDED_SOURCE"])
        self.assertEqual(stats["documents_checked"], 0)


if __name__ == "__main__":
    unittest.main()
