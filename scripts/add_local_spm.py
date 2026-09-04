#!/usr/bin/env python3
"""
Register a local Swift Package Manager package into Stet.xcodeproj/project.pbxproj.

Idempotent: re-running with the same arguments is a no-op.

Example:
    ./scripts/add_local_spm.py \\
        --package-path Packages/StetEngine/Vendor/SherpaOnnxPackage \\
        --product-name sherpa_onnx \\
        --target Stet
"""

import argparse
import hashlib
import re
import sys
from pathlib import Path


def stable_uuid(seed: str) -> str:
    """Pbxproj UUIDs are 24 uppercase hex chars. Deterministic per seed
    so the same package consistently maps to the same UUIDs across runs."""
    digest = hashlib.sha1(seed.encode("utf-8")).hexdigest().upper()
    return digest[:24]


def already_registered(pbx: str, product_name: str) -> bool:
    return f"/* {product_name} in Frameworks */" in pbx


def insert_after(pbx: str, anchor_regex: str, new_block: str, label: str) -> str:
    """Insert `new_block` immediately after the first line matching `anchor_regex`.
    Errors out if the anchor isn't found, so we don't silently corrupt the project."""
    pattern = re.compile(anchor_regex, re.MULTILINE)
    match = pattern.search(pbx)
    if not match:
        sys.exit(f"could not locate anchor for {label!r} in project.pbxproj")
    end = match.end()
    return pbx[:end] + "\n" + new_block.rstrip("\n") + pbx[end:]


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--package-path", required=True, help="Relative path, e.g. Packages/StetEngine/Vendor/SherpaOnnxPackage")
    p.add_argument("--product-name", required=True, help="Product/library name, e.g. sherpa_onnx")
    p.add_argument("--target", default="Stet", help="Target name in pbxproj (default: Stet)")
    p.add_argument(
        "--project",
        default=str(Path(__file__).resolve().parent.parent / "Stet.xcodeproj" / "project.pbxproj"),
        help="Path to project.pbxproj",
    )
    args = p.parse_args()

    pbxproj_path = Path(args.project)
    if not pbxproj_path.exists():
        sys.exit(f"project.pbxproj not found at {pbxproj_path}")

    pbx = pbxproj_path.read_text(encoding="utf-8")

    if already_registered(pbx, args.product_name):
        print(f"[skip] {args.product_name} already registered in {pbxproj_path.name}")
        return 0

    # Three deterministic UUIDs per package, mirroring whisper's E1{11,12,13} convention.
    pkg_ref_uuid = stable_uuid(f"{args.package_path}:pkg")
    product_uuid = stable_uuid(f"{args.package_path}:product:{args.product_name}")
    build_file_uuid = stable_uuid(f"{args.package_path}:build:{args.product_name}")

    # 1. PBXBuildFile entry — "<product> in Frameworks"
    build_file_line = (
        f"\t\t{build_file_uuid} /* {args.product_name} in Frameworks */ = "
        f"{{isa = PBXBuildFile; productRef = {product_uuid} /* {args.product_name} */; }};"
    )
    pbx = insert_after(
        pbx,
        r"^/\* Begin PBXBuildFile section \*/$",
        build_file_line,
        "PBXBuildFile section header",
    )

    # 2. PBXFrameworksBuildPhase — add to the target's frameworks list.
    # We anchor on the first `files = (` inside a Frameworks build phase.
    frameworks_line = f"\t\t\t\t{build_file_uuid} /* {args.product_name} in Frameworks */,"
    fwk_pattern = re.compile(
        r"(/\* Frameworks \*/ = \{\s*isa = PBXFrameworksBuildPhase;[^}]*?files = \()",
        re.DOTALL,
    )
    m = fwk_pattern.search(pbx)
    if not m:
        sys.exit("could not locate PBXFrameworksBuildPhase files list")
    pbx = pbx[: m.end()] + "\n" + frameworks_line + pbx[m.end():]

    # 3. Target's packageProductDependencies — find the `name = <target>;` block, then its packageProductDependencies.
    target_pattern = re.compile(
        rf"(name = {re.escape(args.target)};\s*\n\s*packageProductDependencies = \()",
        re.MULTILINE,
    )
    m = target_pattern.search(pbx)
    if not m:
        sys.exit(f"could not locate packageProductDependencies for target {args.target!r}")
    product_dep_line = f"\t\t\t\t{product_uuid} /* {args.product_name} */,"
    pbx = pbx[: m.end()] + "\n" + product_dep_line + pbx[m.end():]

    # 4. Project's packageReferences list.
    pkg_refs_pattern = re.compile(r"^\s*packageReferences = \(", re.MULTILINE)
    m = pkg_refs_pattern.search(pbx)
    if not m:
        sys.exit("could not locate packageReferences list")
    pkg_ref_line = (
        f"\t\t\t\t{pkg_ref_uuid} /* XCLocalSwiftPackageReference \"{args.package_path}\" */,"
    )
    pbx = pbx[: m.end()] + "\n" + pkg_ref_line + pbx[m.end():]

    # 5. XCLocalSwiftPackageReference — create the section if missing, otherwise insert into it.
    local_ref_block = (
        f"\t\t{pkg_ref_uuid} /* XCLocalSwiftPackageReference \"{args.package_path}\" */ = {{\n"
        f"\t\t\tisa = XCLocalSwiftPackageReference;\n"
        f"\t\t\trelativePath = {args.package_path};\n"
        f"\t\t}};"
    )
    if "/* Begin XCLocalSwiftPackageReference section */" in pbx:
        pbx = insert_after(
            pbx,
            r"^/\* Begin XCLocalSwiftPackageReference section \*/$",
            local_ref_block,
            "XCLocalSwiftPackageReference section header",
        )
    else:
        # Insert a brand-new section before XCRemoteSwiftPackageReference, falling back
        # to before XCSwiftPackageProductDependency if no remote section exists.
        new_section = (
            "\n/* Begin XCLocalSwiftPackageReference section */\n"
            f"{local_ref_block}\n"
            "/* End XCLocalSwiftPackageReference section */\n"
        )
        anchor = "/* Begin XCRemoteSwiftPackageReference section */"
        if anchor not in pbx:
            anchor = "/* Begin XCSwiftPackageProductDependency section */"
        if anchor not in pbx:
            sys.exit("could not find anchor to insert XCLocalSwiftPackageReference section")
        pbx = pbx.replace(anchor, new_section + "\n" + anchor, 1)

    # 6. XCSwiftPackageProductDependency entry.
    product_dep_block = (
        f"\t\t{product_uuid} /* {args.product_name} */ = {{\n"
        f"\t\t\tisa = XCSwiftPackageProductDependency;\n"
        f"\t\t\tpackage = {pkg_ref_uuid} /* XCLocalSwiftPackageReference \"{args.package_path}\" */;\n"
        f"\t\t\tproductName = {args.product_name};\n"
        f"\t\t}};"
    )
    pbx = insert_after(
        pbx,
        r"^/\* Begin XCSwiftPackageProductDependency section \*/$",
        product_dep_block,
        "XCSwiftPackageProductDependency section header",
    )

    pbxproj_path.write_text(pbx, encoding="utf-8")
    print(
        f"[ok] registered {args.product_name} from {args.package_path}\n"
        f"     pkg_ref={pkg_ref_uuid} product={product_uuid} build_file={build_file_uuid}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
