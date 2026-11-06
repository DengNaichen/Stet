#!/usr/bin/env python3
"""Check StetMac against its prescribed architecture rules.

Facts come from tools/deps-graph (swift-syntax). Rules are declared as data
below; each violation is reported with a location and a fix hint so that a
human or an agent can act on it directly.

Baseline (ratchet): existing R4/R5 violations are listed in
scripts/arch-baseline.json. Only violations not in the baseline fail the check;
fixed entries are reported so the baseline can shrink. Strict rules (R0-R6)
can never be baselined.

Usage:
  python3 scripts/arch-check.py            # all rules; exit 1 only on new violations
  python3 scripts/arch-check.py --rule R4  # one rule
  python3 scripts/arch-check.py --summary  # counts only
  python3 scripts/arch-check.py --assume StetMac/Shared/Utilities/Foo.swift=StetMac/Core/Foo/Foo.swift
                                           # what-if: re-check as if files were moved
  python3 scripts/arch-check.py --new-only # only violations not in the baseline
  python3 scripts/arch-check.py --write-baseline
                                           # accept current R4/R5 violations as baseline
  python3 scripts/arch-check.py --print-rules
                                           # compact rules, appended to Stop hook feedback
  python3 scripts/arch-check.py --json     # machine-readable result (Stop hook)

Agent hooks (.claude/settings.json, .codex/hooks.json) call .codex/hooks/arch.py,
which wraps --print-rules and --json; this script stays host-agnostic.
"""
from __future__ import annotations

import argparse
import contextlib
import io
import json
import re
import subprocess
import sys
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "StetMac"
TOOL_DIR = ROOT / "tools" / "deps-graph"
TOOL_BIN = TOOL_DIR / ".build" / "release" / "deps-graph"
BASELINE = ROOT / "scripts" / "arch-baseline.json"

# --- Architecture definition -------------------------------------------------

# Layers, outermost first. A layer may depend on itself and on layers after it.
LAYERS = ["App", "Presentation", "Core", "Shared"]

# Path prefix (under StetMac/) -> layer. Longest prefix wins. Files directly
# under StetMac/ (StetApp.swift, ContentView.swift) are entry points -> App.
# Any other path is unknown and fails R0: new top-level directories must be
# assigned a layer here, never default into the most permissive one.
ROOT_FILES_LAYER = "App"
LAYER_OF_PATH = {
    "App/": "App",
    "Features/": "Presentation",
    "Shared/UI/": "Presentation",  # R3: shared UI components are presentation
    "Core/": "Core",
    "Shared/": "Shared",
}

# Layer -> modules it must not import (R6). AppKit stays allowed in Core: it
# is how macOS exposes pasteboard, workspace, and event APIs.
FORBIDDEN_IMPORTS = {
    "Core": {"SwiftUI"},
    "Shared": {"SwiftUI"},
}

# Rules that are already at zero and must stay there; never baselined.
STRICT_RULES = {"R0", "R1", "R2", "R3", "R4", "R5", "R6", "R7"}

# R5 only counts a View that stores the service. Receiving it in `init` and passing
# it on to a ViewModel (an `injects`-only reference) is the intended composition.
SHARED_ACCESS = re.compile(r"\b([A-Z]\w*)\.shared\b")
STRONG = {"holds"}
SERVICE_KINDS = {"class", "actor", "protocol"}


@dataclass(frozen=True)
class Rule:
    id: str
    title: str
    why: str
    fix: str


RULES = {
    "R0": Rule(
        "R0", "每个文件都必须属于一个已声明的层",
        "未声明的路径若默认归入某层，就会悄悄绕过所有规则。",
        "在 scripts/arch-check.py 的 LAYER_OF_PATH 中为这个目录声明层，或把文件移到已有目录。",
    ),
    "R1": Rule(
        "R1", "依赖方向：App → Presentation → Core → Shared",
        "外层可以依赖内层，内层不知道外层的存在。",
        "把被引用的类型移到更内层，或在内层定义协议、由外层实现。",
    ),
    "R2": Rule(
        "R2", "Shared 不含业务知识，不依赖 app 内任何类型",
        "Shared 是谁都能放心用的基础层；一旦知道业务概念就会和业务形成环。",
        "这个文件知道业务概念，应移到 Core 中对应的能力目录。",
    ),
    "R3": Rule(
        "R3", "Shared/UI 属于展示层，Core 不得引用",
        "Core 是能力层，不应知道界面如何呈现。",
        "Core 需要的展示相关数据应作为值类型放在 Core，由展示层转换。",
    ),
    "R4": Rule(
        "R4", "Presentation 不引用 App 的任何类型（含协议）",
        "App 是组装根，依赖一切；被 Presentation 引用会形成 App ↔ Presentation 环，"
        "Feature 无法独立测试或 Preview。",
        "依赖倒置：把协议定义移到 Presentation（使用方），由 App 中的类型实现；"
        "具体类型（如 MacAppModel）改为注入 ViewModel 或协议。",
    ),
    "R5": Rule(
        "R5", "View 不持有 Core 的服务对象（值类型可以）",
        "MVVM：View 只渲染状态、转发意图；调用服务是 ViewModel 的职责。",
        "在 ViewModel 中持有该服务，View 只读 ViewModel 暴露的状态和方法。",
    ),
    "R7": Rule(
        "R7", "View 不直接访问 Core 的单例（Type.shared）",
        "单例让依赖在 View 里隐形，Preview 和测试无法替换；调用单例是 ViewModel 的职责，"
        "那里的依赖可以通过 init 参数注入。",
        "把 .shared 的使用移到 ViewModel（init 参数默认值可以是 .shared），View 只读 ViewModel。",
    ),
    "R6": Rule(
        "R6", "Core 和 Shared 不 import SwiftUI",
        "SwiftUI 是展示框架；能力层和基础层用了它，就会知道界面如何呈现，"
        "而类型级规则看不到外部框架。",
        "把用到 SwiftUI 的部分（Color、View、Binding 等）移到 Presentation，"
        "Core 只暴露值类型，由展示层转换。",
    ),
}


def layer_of(file: str) -> str | None:
    rel = file.removeprefix("StetMac/")
    if "/" not in rel:
        return ROOT_FILES_LAYER
    matches = [p for p in LAYER_OF_PATH if rel.startswith(p)]
    return LAYER_OF_PATH[max(matches, key=len)] if matches else None


def module_of(file: str) -> str:
    parts = file.removeprefix("StetMac/").split("/")[:-1]
    return "/".join(parts[:2]) or "(root)"


# --- Facts --------------------------------------------------------------------


def load_facts() -> dict:
    if not TOOL_BIN.exists():
        print("building tools/deps-graph (first run only)…", file=sys.stderr)
        subprocess.run(["swift", "build", "-c", "release", "--package-path", str(TOOL_DIR)],
                       check=True, stdout=sys.stderr)
    out = subprocess.run([str(TOOL_BIN), str(SRC)], cwd=ROOT, check=True,
                         capture_output=True, text=True).stdout
    return json.loads(out)


# --- Checks -------------------------------------------------------------------


@dataclass
class Violation:
    rule: str
    file: str
    line: int
    source: str  # referencing type ("" = file scope)
    target: str
    kind: str
    target_kind: str

    @property
    def key(self) -> str:
        # Line numbers are excluded so unrelated edits do not invalidate the baseline.
        return f"{self.rule} {self.file} {self.source or Path(self.file).stem} -> {self.target}"


def load_baseline() -> set[str]:
    if not BASELINE.exists():
        return set()
    return set(json.loads(BASELINE.read_text(encoding="utf-8"))["violations"])


def write_baseline(found: list[Violation]) -> int:
    keys = sorted({x.key for x in found if x.rule not in STRICT_RULES})
    BASELINE.write_text(json.dumps({
        "comment": "Accepted existing violations (ratchet). Remove entries as they are "
                   "fixed; never add new ones by hand. Regenerate with "
                   "`python3 scripts/arch-check.py --write-baseline`.",
        "violations": keys,
    }, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {len(keys)} entries to {BASELINE.relative_to(ROOT)}")
    return 0


def apply_moves(facts: dict, moves: list[tuple[str, str]]) -> None:
    """Rewrite file paths in place, as if `old` prefixes had been moved to `new`."""
    def moved(path: str) -> str:
        for old, new in moves:
            if path == old or path.startswith(old):
                return new + path[len(old):]
        return path
    for d in facts["decls"]:
        d["file"] = moved(d["file"])
    for r in facts["refs"]:
        r["file"] = moved(r["file"])
    for i in facts["imports"]:
        i["file"] = moved(i["file"])


def check(facts: dict) -> list[Violation]:
    decls = {d["name"]: d for d in facts["decls"]}
    views = {d["name"] for d in facts["decls"]
             if layer_of(d["file"]) == "Presentation" and "View" in d["inherits"]}

    def in_view(type_name: str) -> bool:
        parts = type_name.split(".")
        return any(".".join(parts[:i]) in views for i in range(1, len(parts) + 1))

    found: list[Violation] = []

    # R0: fail closed on unknown paths; their references are not checked further.
    files = {d["file"] for d in facts["decls"]} | {r["file"] for r in facts["refs"]} \
        | {i["file"] for i in facts["imports"]}
    unknown = {f for f in files if layer_of(f) is None}
    for f in sorted(unknown):
        found.append(Violation("R0", f, 1, Path(f).stem, str(Path(f).parent) + "/",
                               "path", "unassigned"))

    # R6: forbidden framework imports.
    for i in facts["imports"]:
        layer = layer_of(i["file"])
        if i["module"] in FORBIDDEN_IMPORTS.get(layer, set()):
            found.append(Violation("R6", i["file"], i["line"], Path(i["file"]).stem,
                                   i["module"], "import", "module"))

    for r in facts["refs"]:
        target = decls[r["to"]]
        if r["file"] in unknown or target["file"] in unknown:
            continue
        src_layer, dst_layer = layer_of(r["file"]), layer_of(target["file"])
        v = lambda rule: Violation(rule, r["file"], r["line"], r["from"], r["to"],
                                   r["kind"], target["kind"])

        if LAYERS.index(dst_layer) < LAYERS.index(src_layer):
            # Attribute upward edges to the most specific rule.
            if src_layer == "Shared":
                found.append(v("R2"))
            elif src_layer == "Core" and target["file"].startswith("StetMac/Shared/UI/"):
                found.append(v("R3"))
            elif src_layer == "Presentation" and dst_layer == "App":
                found.append(v("R4"))
            else:
                found.append(v("R1"))

        if (src_layer == "Presentation" and dst_layer == "Core" and r["kind"] in STRONG
                and target["kind"] in SERVICE_KINDS and in_view(r["from"])):
            found.append(v("R5"))

    # R7: a View file reaches for a Core/Shared singleton. The dependency graph does
    # not record member access, so this is a text scan (blind to aliases and to
    # `shared` obtained through inference). Under --assume it only sees files that
    # still exist at their original path.
    view_files: dict[str, str] = {}
    for d in facts["decls"]:
        if layer_of(d["file"]) == "Presentation" and "View" in d["inherits"]:
            view_files.setdefault(d["file"], d["name"])
    singleton_types = {d["name"] for d in facts["decls"]
                       if layer_of(d["file"]) in ("Core", "Shared")
                       and d["kind"] in ("class", "actor", "struct", "enum")}
    for file, view in sorted(view_files.items()):
        path = ROOT / file
        if not path.exists():
            continue
        for n, line in enumerate(path.read_text().splitlines(), 1):
            if line.lstrip().startswith("//"):
                continue
            for m in SHARED_ACCESS.finditer(line):
                if m.group(1) in singleton_types:
                    found.append(Violation("R7", file, n, view, m.group(1),
                                           "shared", "singleton"))
    return found


# --- Report -------------------------------------------------------------------


def report(found: list[Violation], only: str | None, summary: bool,
           only_failing: bool = False) -> None:
    by_rule: dict[str, list[Violation]] = defaultdict(list)
    for x in found:
        by_rule[x.rule].append(x)

    for rid, rule in RULES.items():
        if only and rid != only:
            continue
        items = by_rule.get(rid, [])
        # One line per (source, target) pair; keep the first location and all kinds.
        pairs: dict[tuple[str, str], list[Violation]] = defaultdict(list)
        for x in items:
            pairs[(x.source or Path(x.file).stem, x.target)].append(x)
        if only_failing and not pairs:
            continue
        mark = "✓" if not pairs else "✗"
        print(f"{mark} {rid} {rule.title} — {len(pairs)} 处")
        if summary or not pairs:
            continue
        print(f"    为什么：{rule.why}")
        print(f"    怎么改：{rule.fix}")
        for (src, dst), xs in sorted(pairs.items()):
            first = min(xs, key=lambda x: (x.file, x.line))
            kinds = "/".join(sorted({x.kind for x in xs}))
            tkind = xs[0].target_kind
            print(f"    {first.file}:{first.line}  {src} → {dst} [{tkind}, {kinds}]")
        print()


def summarize(found: list[Violation], baseline: set[str]) -> tuple[list[Violation], set[str]]:
    new = [x for x in found if x.key not in baseline]
    fixed = baseline - {x.key for x in found}
    return new, fixed


def print_rules() -> int:
    """Compact rules for agent feedback. Generated from RULES so it cannot drift."""
    print("Stet macOS architecture rules (enforced by scripts/arch-check.py):")
    print("Layers, outer -> inner: " + " -> ".join(LAYERS)
          + ". Paths: App/ and StetMac/*.swift = App; Features/ and Shared/UI/ = "
            "Presentation; Core/ = Core; other Shared/ = Shared.")
    for rid, rule in RULES.items():
        strict = "must stay 0" if rid in STRICT_RULES else "baselined, must not grow"
        print(f"- {rid} ({strict}): {rule.title}。{rule.why}")
    print("After changing StetMac/ structure or cross-directory references, run "
          "`python3 scripts/arch-check.py --new-only`.")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--rule", choices=sorted(RULES))
    ap.add_argument("--summary", action="store_true")
    ap.add_argument("--new-only", action="store_true",
                    help="only report violations not in the baseline")
    ap.add_argument("--write-baseline", action="store_true")
    ap.add_argument("--print-rules", action="store_true")
    ap.add_argument("--json", action="store_true",
                    help="print {new, baseline, fixed, report} as JSON")
    ap.add_argument("--assume", action="append", default=[], metavar="OLD=NEW",
                    help="pretend a file or directory prefix was moved (repeatable)")
    args = ap.parse_args()
    if args.print_rules:
        return print_rules()
    facts = load_facts()
    apply_moves(facts, [tuple(m.split("=", 1)) for m in args.assume])
    found = check(facts)
    if args.write_baseline:
        return write_baseline(found)
    baseline = load_baseline()
    new, fixed = summarize(found, baseline)
    new_keys = {x.key for x in new}
    accepted = {x.key for x in found} - new_keys
    if args.json:
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            report(new, args.rule, False, only_failing=True)
        print(json.dumps({"new": len(new_keys), "baseline": len(accepted),
                          "fixed": sorted(fixed), "report": buf.getvalue().strip()},
                         ensure_ascii=False))
        return 1 if new else 0
    report(new if args.new_only else found, args.rule, args.summary,
           only_failing=args.new_only)
    print(f"新增 {len(new_keys)} 条（需修复）；基线 {len(accepted)} 条（已接受）"
          + (f"；已修复、可移出基线 {len(fixed)} 条" if fixed else ""))
    for key in sorted(fixed):
        print(f"    可移出基线：{key}")
    return 1 if new else 0


if __name__ == "__main__":
    sys.exit(main())
