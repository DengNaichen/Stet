#!/usr/bin/env node

import { chmod, copyFile, lstat, mkdir, readdir, readlink, stat, symlink } from "node:fs/promises";
import { dirname, isAbsolute, join, relative, resolve, sep } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const defaultSource = resolve(scriptDir, "..", "templates", "init");

export async function materializeInitTemplates(options = {}) {
	const source = resolve(options.source || defaultSource);
	const target = resolve(options.target || process.cwd());
	const report = {
		source,
		target,
		mode: "missing-only",
		created: [],
		skipped_existing: [],
		conflicts: [],
	};

	const files = await listTemplateFiles(source);
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

	report.created.sort();
	report.skipped_existing.sort();
	report.conflicts.sort((a, b) => a.path.localeCompare(b.path));
	return report;
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
		"Usage: node /opt/harnesskit/scripts/init-materialize.mjs [--target <repo-root>] [--source <template-root>]",
		"",
		"Copies missing files from harnesskit/templates/init and creates CLAUDE.md -> AGENTS.md.",
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
