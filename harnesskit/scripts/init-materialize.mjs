#!/usr/bin/env node

import { chmod, copyFile, lstat, mkdir, readdir, readFile, readlink, stat, symlink } from "node:fs/promises";
import { dirname, isAbsolute, join, relative, resolve, sep } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const defaultSource = resolve(scriptDir, "..", "templates", "init");
const artifactManifestPath = ".harnesskit/audit/artifact-manifest.json";
const artifactManifestSchemaVersion = 3;
const claimsDirectory = ".harnesskit/audit/claims";
const namespacePattern = /^[A-Z][A-Z0-9]*(?:-[A-Z][A-Z0-9]*)*$/;
const profileSources = new Map([
	["web-frontend", resolve(scriptDir, "..", "templates", "profiles", "web-frontend")],
]);

export async function materializeInitTemplates(options = {}) {
	const source = resolve(options.source || defaultSource);
	const target = resolve(options.target || process.cwd());
	const profile = selectProfile(options.profile);
	if (profile && source !== defaultSource) {
		throw new Error("a custom template source cannot be combined with --profile");
	}
	const report = {
		source,
		target,
		mode: "missing-only",
		created: [],
		skipped_existing: [],
		conflicts: [],
	};
	if (profile) report.profile = profile.name;

	let files = await listTemplateFiles(source);
	let expectedProfileManifest = null;
	if (profile) {
		const overlayFiles = await listTemplateFiles(profile.source);
		const overlayManifest = overlayFiles.find(({ rel }) => rel === artifactManifestPath);
		if (!overlayManifest) {
			throw new Error(`profile ${profile.name} does not provide ${artifactManifestPath}`);
		}
		expectedProfileManifest = await readManifest(overlayManifest.path);
		if (!validateArtifactManifest(expectedProfileManifest)) {
			throw new Error(`profile ${profile.name} provides an invalid ${artifactManifestPath}`);
		}
		files = overlayTemplateFiles(files, overlayFiles);
	}

	const plan = await preflightMaterialization({
		target,
		files,
		profile,
		expectedProfileManifest,
	});
	report.conflicts.push(...plan.conflicts);
	if (report.conflicts.length > 0) return finalizeReport(report);
	report.skipped_existing.push(...plan.skippedExisting);

	for (const item of plan.createFiles) {
		const targetPath = join(target, item.relNative);
		await mkdir(dirname(targetPath), { recursive: true });
		await copyFile(item.path, targetPath);
		await chmod(targetPath, item.mode & 0o777);
		report.created.push(item.rel);
	}
	if (plan.createClaudeCompanion) {
		await symlink("AGENTS.md", join(target, "CLAUDE.md"));
		report.created.push("CLAUDE.md");
	}

	return finalizeReport(report);
}

function finalizeReport(report) {
	report.created.sort();
	report.skipped_existing.sort();
	report.conflicts.sort((a, b) => a.path.localeCompare(b.path));
	return report;
}

function selectProfile(value) {
	if (value === undefined || value === null) return null;
	const source = typeof value === "string" ? profileSources.get(value) : null;
	if (!source) {
		throw new Error(
			`unknown profile: ${String(value)}; supported profiles: ${[...profileSources.keys()].join(", ")}`,
		);
	}
	return { name: value, source };
}

function overlayTemplateFiles(baseFiles, overlayFiles) {
	const byPath = new Map(baseFiles.map((item) => [item.rel, item]));
	for (const item of overlayFiles) {
		if (byPath.has(item.rel) && item.rel !== artifactManifestPath) {
			throw new Error(`profile overlay conflicts with base template: ${item.rel}`);
		}
		byPath.set(item.rel, item);
	}
	return [...byPath.values()].sort((a, b) => a.rel.localeCompare(b.rel));
}

async function preflightMaterialization({ target, files, profile, expectedProfileManifest }) {
	const plan = {
		createFiles: [],
		createClaudeCompanion: false,
		skippedExisting: [],
		conflicts: [],
	};
	const fileStates = new Map();
	const targetRoot = await lstatMaybe(target);
	if (targetRoot && !targetRoot.isDirectory()) {
		plan.conflicts.push({ path: ".", reason: "target root exists and is not a directory" });
		return plan;
	}

	for (const item of files) {
		const parentConflict = await findParentConflict(target, item.relNative);
		if (parentConflict) {
			addConflict(plan.conflicts, parentConflict);
			fileStates.set(item.rel, "conflict");
			continue;
		}
		const targetPath = join(target, item.relNative);
		const existing = await lstatMaybe(targetPath);
		if (!existing) {
			plan.createFiles.push(item);
			fileStates.set(item.rel, "create");
			continue;
		}
		if (!existing.isFile()) {
			addConflict(plan.conflicts, {
				path: item.rel,
				reason: "target exists and is not a regular file",
			});
			fileStates.set(item.rel, "conflict");
			continue;
		}
		if (profile && item.rel === artifactManifestPath) {
			let actualManifest = null;
			try {
				actualManifest = await readManifest(targetPath);
			} catch {}
			if (
				!validateArtifactManifest(actualManifest) ||
				!manifestContains(actualManifest, expectedProfileManifest)
			) {
				addConflict(plan.conflicts, {
					path: artifactManifestPath,
					reason: `existing manifest is invalid or does not contain the required ${profile.name} registrations`,
				});
				fileStates.set(item.rel, "conflict");
				continue;
			}
		}
		plan.skippedExisting.push(item.rel);
		fileStates.set(item.rel, "existing");
	}

	await preflightClaudeCompanion(target, fileStates, plan);
	if (plan.conflicts.length > 0) {
		plan.createFiles = [];
		plan.createClaudeCompanion = false;
		plan.skippedExisting = [];
	}
	return plan;
}

async function findParentConflict(target, relNative) {
	const parent = dirname(relNative);
	if (parent === ".") return null;
	let current = target;
	let repoPath = "";
	for (const segment of parent.split(sep)) {
		current = join(current, segment);
		repoPath = repoPath ? `${repoPath}/${segment}` : segment;
		const existing = await lstatMaybe(current);
		if (!existing) return null;
		if (!existing.isDirectory()) {
			return { path: repoPath, reason: "target parent exists and is not a directory" };
		}
	}
	return null;
}

function addConflict(conflicts, conflict) {
	if (
		!conflicts.some(
			(existing) => existing.path === conflict.path && existing.reason === conflict.reason,
		)
	) {
		conflicts.push(conflict);
	}
}

async function preflightClaudeCompanion(target, fileStates, plan) {
	const companion = "CLAUDE.md";
	const companionTarget = "AGENTS.md";
	const companionPath = join(target, companion);
	const existing = await lstatMaybe(companionPath);
	const companionState = fileStates.get(companion);
	if (companionState) {
		if (companionState !== "conflict") {
			addConflict(plan.conflicts, {
				path: companion,
				reason: `template file conflicts with required alias to ${companionTarget}`,
			});
		}
		return;
	}

	if (existing) {
		if (existing.isFile()) {
			plan.skippedExisting.push(companion);
			return;
		}
		if (existing.isSymbolicLink()) {
			const actualTarget = await readlink(companionPath);
			if (actualTarget === companionTarget) {
				plan.skippedExisting.push(companion);
			} else {
				addConflict(plan.conflicts, {
					path: companion,
					reason: `target symlink must point to ${companionTarget}`,
				});
			}
			return;
		}
		addConflict(plan.conflicts, {
			path: companion,
			reason: "target exists and is neither a regular file nor the expected symlink",
		});
		return;
	}

	const agentsState = fileStates.get(companionTarget);
	if (agentsState === "create" || agentsState === "existing") {
		plan.createClaudeCompanion = true;
		return;
	}
	if (agentsState === "conflict") return;
	const aliasTarget = await lstatMaybe(join(target, companionTarget));
	if (aliasTarget && aliasTarget.isFile()) {
		plan.createClaudeCompanion = true;
		return;
	}
	addConflict(plan.conflicts, {
		path: companion,
		reason: `cannot create alias because ${companionTarget} is not a regular file`,
	});
}

async function readManifest(path) {
	return JSON.parse(await readFile(path, "utf8"));
}

function manifestContains(actual, expected) {
	const actualNamespaces = new Map(
		actual.claim_namespaces.map((entry) => [entry.namespace, entry]),
	);
	for (const namespace of expected.claim_namespaces) {
		const registered = actualNamespaces.get(namespace.namespace);
		if (
			!registered ||
			registered.display_name !== namespace.display_name ||
			!Number.isSafeInteger(registered.next_number) ||
			registered.next_number < namespace.next_number
		) {
			return false;
		}
	}
	const actualArtifacts = new Map(actual.claim_artifacts.map((entry) => [entry.path, entry]));
	return expected.claim_artifacts.every((artifact) => {
		const registered = actualArtifacts.get(artifact.path);
		return (
			registered &&
			registered.namespace === artifact.namespace &&
			registered.sidecar === artifact.sidecar
		);
	});
}

function validateArtifactManifest(value) {
	if (!isPlainObject(value) || !hasExactKeys(value, ["schema_version", "claim_namespaces", "claim_artifacts"])) {
		return false;
	}
	if (value.schema_version !== artifactManifestSchemaVersion) return false;
	if (!Array.isArray(value.claim_namespaces) || !Array.isArray(value.claim_artifacts)) return false;

	const namespaces = new Set();
	let previousNamespace = null;
	for (const entry of value.claim_namespaces) {
		if (!isPlainObject(entry) || !hasExactKeys(entry, ["namespace", "display_name", "next_number"])) {
			return false;
		}
		if (!namespacePattern.test(entry.namespace)) return false;
		if (typeof entry.display_name !== "string" || !/\S/.test(entry.display_name)) return false;
		if (!Number.isSafeInteger(entry.next_number) || entry.next_number < 1) return false;
		if (namespaces.has(entry.namespace)) return false;
		if (previousNamespace !== null && previousNamespace >= entry.namespace) return false;
		namespaces.add(entry.namespace);
		previousNamespace = entry.namespace;
	}

	const artifactPaths = new Set();
	const sidecarPaths = new Set();
	let previousArtifact = null;
	for (const entry of value.claim_artifacts) {
		if (!isPlainObject(entry) || !hasExactKeys(entry, ["path", "namespace", "sidecar"])) {
			return false;
		}
		if (!isRepoRelativePath(entry.path) || !entry.path.endsWith(".md")) return false;
		if (!namespaces.has(entry.namespace)) return false;
		const sidecarLeaf =
			typeof entry.sidecar === "string" && entry.sidecar.startsWith(`${claimsDirectory}/`)
				? entry.sidecar.slice(claimsDirectory.length + 1)
				: "";
		if (
			!isRepoRelativePath(entry.sidecar) ||
			!sidecarLeaf ||
			sidecarLeaf.length <= ".json".length ||
			sidecarLeaf.includes("/") ||
			!sidecarLeaf.endsWith(".json")
		) {
			return false;
		}
		if (artifactPaths.has(entry.path) || sidecarPaths.has(entry.sidecar)) return false;
		if (previousArtifact !== null && previousArtifact >= entry.path) return false;
		artifactPaths.add(entry.path);
		sidecarPaths.add(entry.sidecar);
		previousArtifact = entry.path;
	}
	return true;
}

function isPlainObject(value) {
	return value !== null && typeof value === "object" && !Array.isArray(value);
}

function hasExactKeys(value, expected) {
	const actual = Object.keys(value).sort();
	const sortedExpected = [...expected].sort();
	return (
		actual.length === sortedExpected.length &&
		actual.every((key, index) => key === sortedExpected[index])
	);
}

function isRepoRelativePath(value) {
	if (typeof value !== "string" || value.length === 0 || !/^\S+$/.test(value)) return false;
	if (isAbsolute(value) || /^(?:\/|[A-Za-z]:)/.test(value)) return false;
	if (value.includes("\\") || value.includes(":") || /[\u0000-\u001f\u007f]/.test(value)) return false;
	return value.split("/").every((segment) => segment !== "" && segment !== "." && segment !== "..");
}

async function listTemplateFiles(source) {
	const root = resolve(source);
	const rootStat = await stat(root);
	if (!rootStat.isDirectory()) {
		throw new Error(`template source is not a directory: ${root}`);
	}

	const out = [];
	await walk(root, root, out);
	out.sort((a, b) => a.rel.localeCompare(b.rel));
	return out;
}

async function walk(root, dir, out) {
	const entries = await readdir(dir, { withFileTypes: true });
	entries.sort((a, b) => a.name.localeCompare(b.name));
	for (const entry of entries) {
		const path = join(dir, entry.name);
		if (entry.isDirectory()) {
			await walk(root, path, out);
			continue;
		}
		if (!entry.isFile()) {
			continue;
		}
		const relNative = relative(root, path);
		const rel = relNative.split(sep).join("/");
		validateTemplatePath(rel, path, root);
		const fileStat = await stat(path);
		out.push({ path, relNative, rel, mode: fileStat.mode });
	}
}

function validateTemplatePath(rel, fullPath, root) {
	if (!rel || isAbsolute(rel) || rel.split("/").some((part) => part === "." || part === "..")) {
		throw new Error(`invalid template path: ${rel}`);
	}
	const resolved = resolve(fullPath);
	if (resolved !== root && !resolved.startsWith(`${root}${sep}`)) {
		throw new Error(`template path escapes source root: ${rel}`);
	}
}

async function lstatMaybe(path) {
	try {
		return await lstat(path);
	} catch (error) {
		if (error && error.code === "ENOENT") {
			return null;
		}
		throw error;
	}
}

function parseArgs(argv) {
	const options = {};
	for (let i = 0; i < argv.length; i += 1) {
		const arg = argv[i];
		if (arg === "--target") {
			i += 1;
			if (!argv[i]) {
				throw new Error("--target requires a value");
			}
			options.target = argv[i];
			continue;
		}
		if (arg === "--source") {
			i += 1;
			if (!argv[i]) {
				throw new Error("--source requires a value");
			}
			options.source = argv[i];
			continue;
		}
		if (arg === "--profile") {
			i += 1;
			if (!argv[i]) {
				throw new Error("--profile requires a value");
			}
			options.profile = argv[i];
			continue;
		}
		if (arg === "--help" || arg === "-h") {
			options.help = true;
			continue;
		}
		throw new Error(`unknown argument: ${arg}`);
	}
	return options;
}

function usage() {
	return [
		"Usage: node /opt/harnesskit/scripts/init-materialize.mjs [--target <repo-root>] [--source <template-root>] [--profile <profile>]",
		"",
		"Copies missing files from harnesskit/templates/init and creates CLAUDE.md -> AGENTS.md.",
		"Use --profile web-frontend to add the Web frontend artifact overlay.",
		"A custom --source cannot be combined with --profile.",
		"Existing files are never overwritten.",
	].join("\n");
}

async function main() {
	const options = parseArgs(process.argv.slice(2));
	if (options.help) {
		process.stdout.write(`${usage()}\n`);
		return;
	}
	const report = await materializeInitTemplates(options);
	process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
	if (report.conflicts.length > 0) {
		process.exitCode = 1;
	}
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
	main().catch((error) => {
		process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
		process.exitCode = 1;
	});
}
