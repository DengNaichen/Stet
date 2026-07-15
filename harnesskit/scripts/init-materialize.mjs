#!/usr/bin/env node

import { chmod, copyFile, lstat, mkdir, readdir, readFile, readlink, stat, symlink } from "node:fs/promises";
import { dirname, isAbsolute, join, relative, resolve, sep } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const defaultSource = resolve(scriptDir, "..", "templates", "init");
const artifactManifestPath = ".harnesskit/audit/artifact-manifest.json";
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
	if (profile) {
		const overlayFiles = await listTemplateFiles(profile.source);
		const overlayManifest = overlayFiles.find(({ rel }) => rel === artifactManifestPath);
		if (!overlayManifest) {
			throw new Error(`profile ${profile.name} does not provide ${artifactManifestPath}`);
		}
		const manifestConflict = await findProfileManifestConflict(
			target,
			overlayManifest.path,
			profile.name,
		);
		if (manifestConflict) {
			report.conflicts.push(manifestConflict);
			return finalizeReport(report);
		}
		files = overlayTemplateFiles(files, overlayFiles);
	}
	for (const item of files) {
		const targetPath = join(target, item.relNative);
		const existing = await lstatMaybe(targetPath);
		if (existing) {
			if (existing.isFile()) {
				report.skipped_existing.push(item.rel);
			} else {
				report.conflicts.push({ path: item.rel, reason: "target exists and is not a regular file" });
			}
			continue;
		}

		await mkdir(dirname(targetPath), { recursive: true });
		await copyFile(item.path, targetPath);
		await chmod(targetPath, item.mode & 0o777);
		report.created.push(item.rel);
	}

	await materializeClaudeCompanion(target, report);

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

async function findProfileManifestConflict(target, expectedPath, profile) {
	const targetPath = join(target, ...artifactManifestPath.split("/"));
	const existing = await lstatMaybe(targetPath);
	if (!existing) return null;
	if (!existing.isFile()) {
		return { path: artifactManifestPath, reason: "target exists and is not a regular file" };
	}

	let actual;
	let expected;
	try {
		[actual, expected] = await Promise.all([
			readFile(targetPath, "utf8").then(JSON.parse),
			readFile(expectedPath, "utf8").then(JSON.parse),
		]);
	} catch {
		return {
			path: artifactManifestPath,
			reason: `existing manifest does not contain the required ${profile} registrations`,
		};
	}
	if (!manifestContains(actual, expected)) {
		return {
			path: artifactManifestPath,
			reason: `existing manifest does not contain the required ${profile} registrations`,
		};
	}
	return null;
}

function manifestContains(actual, expected) {
	if (
		!actual ||
		!expected ||
		!Array.isArray(actual.claim_namespaces) ||
		!Array.isArray(expected.claim_namespaces) ||
		!Array.isArray(actual.claim_artifacts) ||
		!Array.isArray(expected.claim_artifacts)
	) {
		return false;
	}
	const actualNamespaces = new Map(
		actual.claim_namespaces.map((entry) => [entry && entry.namespace, entry]),
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
	const actualArtifacts = new Map(actual.claim_artifacts.map((entry) => [entry && entry.path, entry]));
	return expected.claim_artifacts.every((artifact) => {
		const registered = actualArtifacts.get(artifact.path);
		return (
			registered &&
			registered.namespace === artifact.namespace &&
			registered.sidecar === artifact.sidecar
		);
	});
}

async function materializeClaudeCompanion(target, report) {
	const companion = "CLAUDE.md";
	const companionTarget = "AGENTS.md";
	const companionPath = join(target, companion);
	const existing = await lstatMaybe(companionPath);

	if (existing) {
		if (existing.isFile()) {
			report.skipped_existing.push(companion);
			return;
		}
		if (existing.isSymbolicLink()) {
			const actualTarget = await readlink(companionPath);
			if (actualTarget === companionTarget) {
				report.skipped_existing.push(companion);
			} else {
				report.conflicts.push({
					path: companion,
					reason: `target symlink must point to ${companionTarget}`,
				});
			}
			return;
		}
		report.conflicts.push({
			path: companion,
			reason: "target exists and is neither a regular file nor the expected symlink",
		});
		return;
	}

	const aliasTarget = await lstatMaybe(join(target, companionTarget));
	if (!aliasTarget || !aliasTarget.isFile()) {
		report.conflicts.push({
			path: companion,
			reason: `cannot create alias because ${companionTarget} is not a regular file`,
		});
		return;
	}

	await symlink(companionTarget, companionPath);
	report.created.push(companion);
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
