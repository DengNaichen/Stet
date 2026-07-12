#!/usr/bin/env node

import { createHash } from "node:crypto";
import { execFile as execFileCallback } from "node:child_process";
import { lstat, readFile, readlink, readdir, realpath } from "node:fs/promises";
import { basename, dirname, isAbsolute, relative, resolve, sep } from "node:path";
import { promisify } from "node:util";
import { fileURLToPath } from "node:url";

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const lockPath = resolve(repoRoot, ".harnesskit/assets.lock.json");
const execFile = promisify(execFileCallback);
const violations = [];

function addViolation(code, path, message) {
  violations.push({ code, path, message });
}

function isSafeRepoRelative(path) {
  return (
    typeof path === "string" &&
    path.length > 0 &&
    !isAbsolute(path) &&
    !path.split(/[\\/]/).includes("..")
  );
}

function isInside(root, path) {
  const child = relative(root, path);
  return child === "" || (!child.startsWith(`..${sep}`) && child !== ".." && !isAbsolute(child));
}

async function sha256(path) {
  return createHash("sha256").update(await readFile(path)).digest("hex");
}

async function listSnapshotFiles(relativeRoot) {
  const results = [];

  async function visit(relativeDirectory) {
    const absoluteDirectory = resolve(repoRoot, relativeDirectory);
    for (const entry of await readdir(absoluteDirectory, { withFileTypes: true })) {
      const relativePath = `${relativeDirectory}/${entry.name}`;
      if (entry.isDirectory()) {
        await visit(relativePath);
      } else if (entry.isFile()) {
        results.push(relativePath);
      } else {
        addViolation("unexpected_snapshot_entry", relativePath, "Snapshot entries must be regular files or directories.");
      }
    }
  }

  await visit(relativeRoot);
  return results.sort();
}

function parseArgs(argv) {
  let sourceRoot = null;
  for (let index = 0; index < argv.length; index += 1) {
    if (argv[index] !== "--source-root" || !argv[index + 1]) {
      throw new Error("Usage: node scripts/verify-harnesskit-assets.mjs [--source-root <path>]");
    }
    sourceRoot = resolve(argv[index + 1]);
    index += 1;
  }
  return { sourceRoot };
}

async function main() {
  let options;
  try {
    options = parseArgs(process.argv.slice(2));
  } catch (error) {
    addViolation("invalid_args", "argv", String(error));
    return report(null, [], [], 0);
  }

  let manifest;
  try {
    manifest = JSON.parse(await readFile(lockPath, "utf8"));
  } catch (error) {
    addViolation("invalid_lock", ".harnesskit/assets.lock.json", String(error));
    return report(null, [], [], 0);
  }

  const files = Array.isArray(manifest.files) ? manifest.files : [];
  const bridges = Array.isArray(manifest.discovery_bridges) ? manifest.discovery_bridges : [];
  let checkedSourceFiles = 0;
  if (options.sourceRoot) {
    try {
      const { stdout } = await execFile("git", ["-C", options.sourceRoot, "rev-parse", "HEAD"]);
      const actualCommit = stdout.trim();
      if (actualCommit !== manifest?.source?.commit) {
        addViolation(
          "source_commit_mismatch",
          "source",
          `expected ${manifest?.source?.commit ?? "<missing>"}, got ${actualCommit}.`
        );
      }
    } catch (error) {
      addViolation("invalid_source_repository", "source", String(error));
    }

    for (const file of files) {
      if (!isSafeRepoRelative(file?.source) || !file.source.startsWith("harnesskit/")) continue;
      const absoluteSource = resolve(options.sourceRoot, file.source);
      if (!isInside(options.sourceRoot, absoluteSource)) {
        addViolation("unsafe_source", file.source, "source resolves outside the source repository.");
        continue;
      }
      try {
        const stats = await lstat(absoluteSource);
        if (!stats.isFile()) {
          addViolation("invalid_source_type", file.source, "source must be a regular file.");
          continue;
        }
        const executable = (stats.mode & 0o111) !== 0;
        if (typeof file.executable === "boolean" && executable !== file.executable) {
          addViolation("source_mode_mismatch", file.source, `expected executable=${file.executable}, got ${executable}.`);
        }
        const actual = await sha256(absoluteSource);
        if (actual !== file.sha256) {
          addViolation("source_hash_mismatch", file.source, `expected ${file.sha256}, got ${actual}.`);
        }
        checkedSourceFiles += 1;
      } catch (error) {
        addViolation("missing_source", file.source, String(error));
      }
    }
  }

  if (manifest.schema_version !== 1) {
    addViolation("invalid_lock", ".harnesskit/assets.lock.json", "schema_version must equal 1.");
  }

  if (!Array.isArray(manifest.files)) {
    addViolation("invalid_lock", ".harnesskit/assets.lock.json", "files must be an array.");
  }
  if (!Array.isArray(manifest.discovery_bridges)) {
    addViolation("invalid_lock", ".harnesskit/assets.lock.json", "discovery_bridges must be an array.");
  }

  const seenSources = new Set();
  const seenTargets = new Set();

  for (const file of files) {
    const label = typeof file?.target === "string" ? file.target : "<unknown>";
    if (!isSafeRepoRelative(file?.source) || !file.source.startsWith("harnesskit/")) {
      addViolation("invalid_source_path", label, "source must be a safe harnesskit/ repo-relative path.");
    } else if (seenSources.has(file.source)) {
      addViolation("duplicate_source", file.source, "source appears more than once.");
    } else {
      seenSources.add(file.source);
    }

    if (!isSafeRepoRelative(file?.target) || !file.target.startsWith("harnesskit/")) {
      addViolation("invalid_target_path", label, "target must be a safe harnesskit/ repo-relative path.");
      continue;
    }
    if (seenTargets.has(file.target)) {
      addViolation("duplicate_target", file.target, "target appears more than once.");
      continue;
    }
    seenTargets.add(file.target);

    if (!/^[0-9a-f]{64}$/.test(file.sha256 ?? "")) {
      addViolation("invalid_sha256", file.target, "sha256 must be lowercase hexadecimal.");
      continue;
    }
    if (typeof file.executable !== "boolean") {
      addViolation("invalid_mode", file.target, "executable must be boolean.");
    }

    const absoluteTarget = resolve(repoRoot, file.target);
    if (!isInside(repoRoot, absoluteTarget)) {
      addViolation("unsafe_target", file.target, "target resolves outside the repository.");
      continue;
    }

    try {
      const stats = await lstat(absoluteTarget);
      if (!stats.isFile()) {
        addViolation("invalid_target_type", file.target, "target must be a regular file.");
        continue;
      }
      const executable = (stats.mode & 0o111) !== 0;
      if (typeof file.executable === "boolean" && executable !== file.executable) {
        addViolation("mode_mismatch", file.target, `expected executable=${file.executable}, got ${executable}.`);
      }
      const actual = await sha256(absoluteTarget);
      if (actual !== file.sha256) {
        addViolation("hash_mismatch", file.target, `expected ${file.sha256}, got ${actual}.`);
      }
    } catch (error) {
      addViolation("missing_target", file.target, String(error));
    }
  }

  let snapshotFiles = [];
  try {
    snapshotFiles = await listSnapshotFiles("harnesskit");
    for (const path of snapshotFiles) {
      if (!seenTargets.has(path)) {
        addViolation("unmapped_snapshot_file", path, "Every file under harnesskit/ must be recorded in the lock.");
      }
    }
    for (const path of seenTargets) {
      if (!snapshotFiles.includes(path)) {
        addViolation("missing_snapshot_file", path, "Locked target is missing from harnesskit/.");
      }
    }
  } catch (error) {
    addViolation("invalid_snapshot", "harnesskit", String(error));
  }

  const seenLinks = new Set();
  for (const bridge of bridges) {
    const label = typeof bridge?.link === "string" ? bridge.link : "<unknown>";
    if (!isSafeRepoRelative(bridge?.link) || !bridge.link.startsWith(".agents/skills/")) {
      addViolation("invalid_bridge_path", label, "link must be a safe .agents/skills/ repo-relative path.");
      continue;
    }
    if (seenLinks.has(bridge.link)) {
      addViolation("duplicate_bridge", bridge.link, "link appears more than once.");
      continue;
    }
    seenLinks.add(bridge.link);

    if (typeof bridge.target !== "string" || bridge.target.length === 0 || isAbsolute(bridge.target)) {
      addViolation("invalid_bridge_target", bridge.link, "target must be a non-empty relative symlink target.");
      continue;
    }

    const linkPath = resolve(repoRoot, bridge.link);
    try {
      const stats = await lstat(linkPath);
      if (!stats.isSymbolicLink()) {
        addViolation("invalid_bridge_type", bridge.link, "discovery bridge must be a symlink.");
        continue;
      }
      const rawTarget = await readlink(linkPath);
      if (rawTarget !== bridge.target) {
        addViolation("bridge_target_mismatch", bridge.link, `expected ${bridge.target}, got ${rawTarget}.`);
      }

      const resolvedTarget = await realpath(linkPath);
      if (!isInside(repoRoot, resolvedTarget)) {
        addViolation("unsafe_bridge_target", bridge.link, "bridge resolves outside the repository.");
        continue;
      }

      const expectedTarget = await realpath(resolve(dirname(linkPath), bridge.target));
      if (resolvedTarget !== expectedTarget) {
        addViolation("bridge_realpath_mismatch", bridge.link, "bridge does not resolve to its locked target.");
      }

      const skillName = basename(bridge.link);
      const skillBody = await readFile(resolve(resolvedTarget, "SKILL.md"), "utf8");
      const escapedName = skillName.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      if (!new RegExp(`^name:\\s*${escapedName}\\s*$`, "m").test(skillBody)) {
        addViolation("skill_name_mismatch", bridge.link, `SKILL.md frontmatter must declare name: ${skillName}.`);
      }
    } catch (error) {
      addViolation("invalid_bridge", bridge.link, String(error));
    }
  }

  report(manifest, snapshotFiles, bridges, checkedSourceFiles);
}

function report(manifest, snapshotFiles, bridges, checkedSourceFiles) {
  const result = {
    status: violations.length === 0 ? "passed" : "failed",
    source_commit: manifest?.source?.commit ?? null,
    target_baseline: manifest?.target?.baseline_commit ?? null,
    source_files_checked: checkedSourceFiles,
    checked_files: snapshotFiles.length,
    checked_bridges: bridges.length,
    violations
  };
  process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
  if (violations.length > 0) process.exitCode = 1;
}

await main();
