#!/usr/bin/env node
"use strict";

const { createHash } = require("node:crypto");
const {
	closeSync,
	constants,
	existsSync,
	linkSync,
	lstatSync,
	mkdirSync,
	openSync,
	readFileSync,
	readSync,
	readdirSync,
	realpathSync,
	renameSync,
	rmSync,
	writeFileSync,
} = require("node:fs");
const { basename, dirname, isAbsolute, join, resolve, sep } = require("node:path");

const CLAIM_SCHEMA_NAME = "claim-v1";
const CLAIM_SCHEMA_VERSION = 4;
const ARTIFACT_MANIFEST_SCHEMA_VERSION = 3;
const CONFIRMATION_SCHEMA_VERSION = 1;
const REPORT_SCHEMA_VERSION = 1;
const ARTIFACT_MANIFEST_PATH = ".harnesskit/audit/artifact-manifest.json";
const CLAIMS_DIR = ".harnesskit/audit/claims";
const TRANSCRIPT_DIR = ".harnesskit/audit/transcript";
const CLAIM_TOOL_LOCK_PATH = ".harnesskit/audit/.claim-contract.lock";
const NAMESPACE_PATTERN = /^[A-Z][A-Z0-9]*(?:-[A-Z][A-Z0-9]*)*$/;
const SHA256_PATTERN = /^[a-f0-9]{64}$/;
const DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;
const CONFIRMATION_TYPES = new Set(["user", "adr", "policy"]);
let temporaryFileCounter = 0;
const lockWaitArray = new Int32Array(new SharedArrayBuffer(4));

function compareText(left, right) {
	if (left < right) return -1;
	if (left > right) return 1;
	return 0;
}

function isPlainObject(value) {
	return value !== null && typeof value === "object" && !Array.isArray(value);
}

function hasNonWhitespace(value) {
	return typeof value === "string" && /\S/.test(value);
}

function isRepoRelativePath(value) {
	if (typeof value !== "string" || value.length === 0 || !/^\S+$/.test(value)) return false;
	if (isAbsolute(value) || /^(?:\/|[A-Za-z]:)/.test(value)) return false;
	if (value.includes("\\") || value.includes(":") || /[\u0000-\u001f\u007f]/.test(value)) return false;
	const segments = value.split("/");
	return segments.every((segment) => segment !== "" && segment !== "." && segment !== "..");
}

function isCalendarDate(value) {
	if (typeof value !== "string" || !DATE_PATTERN.test(value)) return false;
	const [year, month, day] = value.split("-").map(Number);
	const date = new Date(Date.UTC(year, month - 1, day));
	return (
		date.getUTCFullYear() === year &&
		date.getUTCMonth() === month - 1 &&
		date.getUTCDate() === day
	);
}

function canonicalJSONStringify(value) {
	return `${JSON.stringify(value, null, 2)}\n`;
}

function sleepSync(milliseconds) {
	Atomics.wait(lockWaitArray, 0, 0, milliseconds);
}

function processIsAlive(pid) {
	if (!Number.isSafeInteger(pid) || pid < 1) return false;
	try {
		process.kill(pid, 0);
		return true;
	} catch (error) {
		return Boolean(error && error.code === "EPERM");
	}
}

function knownKeys(value, allowed) {
	return Object.keys(value).filter((key) => !allowed.has(key));
}

function exactKeys(value, expected) {
	if (!isPlainObject(value)) return false;
	const actual = Object.keys(value).sort(compareText);
	return actual.length === expected.length && actual.every((key, index) => key === [...expected].sort(compareText)[index]);
}

function safeRegularFile(root, repoPath) {
	if (!isRepoRelativePath(repoPath)) return { ok: false, reason: "unsafe_path" };
	const absoluteRoot = resolve(root);
	let current = absoluteRoot;
	const segments = repoPath.split("/");
	for (let index = 0; index < segments.length; index += 1) {
		current = join(current, segments[index]);
		let info;
		try {
			info = lstatSync(current);
		} catch (error) {
			if (error && error.code === "ENOENT") return { ok: false, reason: "missing" };
			return { ok: false, reason: "unreadable" };
		}
		if (info.isSymbolicLink()) return { ok: false, reason: "symlink" };
		if (index < segments.length - 1 && !info.isDirectory()) {
			return { ok: false, reason: "not_directory" };
		}
	}
	let info;
	try {
		info = lstatSync(current);
	} catch {
		return { ok: false, reason: "unreadable" };
	}
	if (!info.isFile()) return { ok: false, reason: "not_regular_file" };
	let realRoot;
	let realFile;
	try {
		realRoot = realpathSync(absoluteRoot);
		realFile = realpathSync(current);
	} catch {
		return { ok: false, reason: "unreadable" };
	}
	if (realFile !== realRoot && !realFile.startsWith(`${realRoot}${sep}`)) {
		return { ok: false, reason: "outside_repository" };
	}
	return { ok: true, path: current, dev: info.dev, ino: info.ino };
}

function safeExistingDirectory(root, repoPath) {
	if (!isRepoRelativePath(repoPath)) return { ok: false, reason: "unsafe_path" };
	let current = resolve(root);
	for (const segment of repoPath.split("/")) {
		current = join(current, segment);
		let info;
		try {
			info = lstatSync(current);
		} catch (error) {
			if (error && error.code === "ENOENT") return { ok: false, reason: "missing" };
			return { ok: false, reason: "unreadable" };
		}
		if (info.isSymbolicLink()) return { ok: false, reason: "symlink" };
		if (!info.isDirectory()) return { ok: false, reason: "not_directory" };
	}
	return { ok: true, path: current };
}

function sameFileIdentity(left, right) {
	return left.ok && right.ok && left.dev === right.dev && left.ino === right.ino;
}

function readFileWithoutFollowingSymlink(path) {
	const descriptor = openSync(path, constants.O_RDONLY | (constants.O_NOFOLLOW || 0));
	try {
		return readFileSync(descriptor);
	} finally {
		closeSync(descriptor);
	}
}

function sha256FileWithoutFollowingSymlink(path) {
	const descriptor = openSync(path, constants.O_RDONLY | (constants.O_NOFOLLOW || 0));
	const hash = createHash("sha256");
	const buffer = Buffer.allocUnsafe(64 * 1024);
	try {
		let count;
		do {
			count = readSync(descriptor, buffer, 0, buffer.length, null);
			if (count > 0) hash.update(buffer.subarray(0, count));
		} while (count > 0);
		return hash.digest("hex");
	} finally {
		closeSync(descriptor);
	}
}

function hashRepoFile(root, repoPath) {
	const file = safeRegularFile(root, repoPath);
	if (!file.ok) throw new Error(`${repoPath}: ${file.reason}`);
	return sha256FileWithoutFollowingSymlink(file.path);
}

function ensureSafeDirectory(root, repoPath) {
	if (!isRepoRelativePath(repoPath)) throw new Error(`${repoPath}: unsafe_path`);
	const absoluteRoot = resolve(root);
	let current = absoluteRoot;
	for (const segment of repoPath.split("/")) {
		current = join(current, segment);
		try {
			const info = lstatSync(current);
			if (info.isSymbolicLink() || !info.isDirectory()) {
				throw new Error(`${repoPath}: unsafe parent directory`);
			}
		} catch (error) {
			if (!error || error.code !== "ENOENT") throw error;
			mkdirSync(current, { mode: 0o755 });
		}
	}
}

function lockIsStale(lockPath) {
	const info = lstatSync(lockPath);
	if (info.isSymbolicLink() || !info.isDirectory()) {
		throw new Error(`${CLAIM_TOOL_LOCK_PATH}: unsafe lock path`);
	}
	try {
		const owner = JSON.parse(readFileSync(join(lockPath, "owner.json"), "utf8"));
		return !processIsAlive(owner.pid);
	} catch {
		return Date.now() - info.mtimeMs > 30_000;
	}
}

function withClaimContractLock(root, callback) {
	const parent = safeExistingDirectory(root, dirname(CLAIM_TOOL_LOCK_PATH));
	if (!parent.ok) throw new Error(`${dirname(CLAIM_TOOL_LOCK_PATH)}: ${parent.reason}`);
	const lockPath = join(resolve(root), ...CLAIM_TOOL_LOCK_PATH.split("/"));
	const deadline = Date.now() + 10_000;
	while (true) {
		try {
			mkdirSync(lockPath, { mode: 0o700 });
			try {
				writeFileSync(join(lockPath, "owner.json"), canonicalJSONStringify({ pid: process.pid }), {
					encoding: "utf8",
					flag: "wx",
					mode: 0o600,
				});
			} catch (error) {
				rmSync(lockPath, { recursive: true, force: true });
				throw error;
			}
			break;
		} catch (error) {
			if (!error || error.code !== "EEXIST") throw error;
			if (Date.now() >= deadline) {
				let stale;
				try {
					stale = lockIsStale(lockPath);
				} catch (lockError) {
					if (lockError && lockError.code === "ENOENT") continue;
					throw lockError;
				}
				const reason = stale ? "stale writer lock must be removed" : "timed out waiting for writer lock";
				throw new Error(`${CLAIM_TOOL_LOCK_PATH}: ${reason}`);
			}
			sleepSync(10);
		}
	}
	try {
		return callback();
	} finally {
		rmSync(lockPath, { recursive: true, force: true });
	}
}

function writeRepoJSON(root, repoPath, value) {
	if (!isRepoRelativePath(repoPath)) throw new Error(`${repoPath}: unsafe_path`);
	ensureSafeDirectory(root, dirname(repoPath));
	const absolutePath = join(resolve(root), ...repoPath.split("/"));
	try {
		const info = lstatSync(absolutePath);
		if (info.isSymbolicLink() || !info.isFile()) throw new Error(`${repoPath}: unsafe target`);
	} catch (error) {
		if (!error || error.code !== "ENOENT") throw error;
	}
	const temporaryPath = join(
		dirname(absolutePath),
		`.${basename(absolutePath)}.tmp-${process.pid}-${temporaryFileCounter++}`,
	);
	try {
		writeFileSync(temporaryPath, canonicalJSONStringify(value), { encoding: "utf8", flag: "wx", mode: 0o644 });
		renameSync(temporaryPath, absolutePath);
	} catch (error) {
		try {
			rmSync(temporaryPath, { force: true });
		} catch {}
		throw error;
	}
}

function writeImmutableRepoJSON(root, repoPath, value) {
	if (!isRepoRelativePath(repoPath)) throw new Error(`${repoPath}: unsafe_path`);
	ensureSafeDirectory(root, dirname(repoPath));
	const absolutePath = join(resolve(root), ...repoPath.split("/"));
	const serialized = canonicalJSONStringify(value);
	const temporaryPath = join(
		dirname(absolutePath),
		`.${basename(absolutePath)}.tmp-${process.pid}-${temporaryFileCounter++}`,
	);
	try {
		writeFileSync(temporaryPath, serialized, { encoding: "utf8", flag: "wx", mode: 0o644 });
		try {
			linkSync(temporaryPath, absolutePath);
			return;
		} catch (error) {
			if (!error || error.code !== "EEXIST") throw error;
			const existing = safeRegularFile(root, repoPath);
			if (!existing.ok) throw new Error(`${repoPath}: ${existing.reason}`);
			if (readFileWithoutFollowingSymlink(existing.path).toString("utf8") !== serialized) {
				throw new Error(`${repoPath}: confirmation records are immutable`);
			}
		}
	} finally {
		rmSync(temporaryPath, { force: true });
	}
}

function readRepoJSON(root, repoPath) {
	const file = safeRegularFile(root, repoPath);
	if (!file.ok) throw new Error(`${repoPath}: ${file.reason}`);
	let contents;
	try {
		contents = readFileWithoutFollowingSymlink(file.path).toString("utf8");
	} catch {
		throw new Error(`${repoPath}: unreadable`);
	}
	try {
		return JSON.parse(contents);
	} catch {
		throw new Error(`${repoPath}: invalid JSON`);
	}
}

function validateArtifactManifest(value) {
	const errors = [];
	if (!isPlainObject(value)) return ["manifest must be an object"];
	const allowedTopLevel = new Set(["schema_version", "claim_namespaces", "claim_artifacts"]);
	for (const key of knownKeys(value, allowedTopLevel)) errors.push(`unknown field ${key}`);
	for (const key of allowedTopLevel) {
		if (!Object.hasOwn(value, key)) errors.push(`missing field ${key}`);
	}
	if (value.schema_version !== ARTIFACT_MANIFEST_SCHEMA_VERSION) {
		errors.push(`schema_version must equal ${ARTIFACT_MANIFEST_SCHEMA_VERSION}`);
	}
	if (!Array.isArray(value.claim_namespaces)) {
		errors.push("claim_namespaces must be an array");
	} else {
		const seen = new Set();
		let previous = null;
		for (let index = 0; index < value.claim_namespaces.length; index += 1) {
			const entry = value.claim_namespaces[index];
			const pointer = `claim_namespaces[${index}]`;
			if (!isPlainObject(entry)) {
				errors.push(`${pointer} must be an object`);
				continue;
			}
			for (const key of knownKeys(entry, new Set(["namespace", "display_name", "next_number"]))) {
				errors.push(`${pointer} has unknown field ${key}`);
			}
			if (!NAMESPACE_PATTERN.test(entry.namespace || "")) errors.push(`${pointer}.namespace is invalid`);
			if (!hasNonWhitespace(entry.display_name)) errors.push(`${pointer}.display_name is invalid`);
			if (!Number.isSafeInteger(entry.next_number) || entry.next_number < 1) {
				errors.push(`${pointer}.next_number must be a positive safe integer`);
			}
			if (seen.has(entry.namespace)) errors.push(`${pointer}.namespace is duplicated`);
			seen.add(entry.namespace);
			if (previous !== null && compareText(previous, entry.namespace) >= 0) {
				errors.push("claim_namespaces must be strictly sorted by namespace");
			}
			previous = entry.namespace;
		}
	}
	if (!Array.isArray(value.claim_artifacts)) {
		errors.push("claim_artifacts must be an array");
	} else {
		const namespaces = new Set(
			Array.isArray(value.claim_namespaces) ? value.claim_namespaces.map((entry) => entry && entry.namespace) : [],
		);
		const paths = new Set();
		const sidecars = new Set();
		let previous = null;
		for (let index = 0; index < value.claim_artifacts.length; index += 1) {
			const entry = value.claim_artifacts[index];
			const pointer = `claim_artifacts[${index}]`;
			if (!isPlainObject(entry)) {
				errors.push(`${pointer} must be an object`);
				continue;
			}
			for (const key of knownKeys(entry, new Set(["path", "namespace", "sidecar"]))) {
				errors.push(`${pointer} has unknown field ${key}`);
			}
			if (!isRepoRelativePath(entry.path) || !entry.path.endsWith(".md")) {
				errors.push(`${pointer}.path must be a safe Markdown repo path`);
			}
			if (!namespaces.has(entry.namespace)) errors.push(`${pointer}.namespace is not registered`);
			if (
				!isRepoRelativePath(entry.sidecar) ||
				!entry.sidecar.startsWith(`${CLAIMS_DIR}/`) ||
				entry.sidecar.slice(CLAIMS_DIR.length + 1).length <= ".json".length ||
				entry.sidecar.slice(CLAIMS_DIR.length + 1).includes("/") ||
				!entry.sidecar.endsWith(".json")
			) {
				errors.push(`${pointer}.sidecar must be a direct JSON child of ${CLAIMS_DIR}`);
			}
			if (paths.has(entry.path)) errors.push(`${pointer}.path is duplicated`);
			if (sidecars.has(entry.sidecar)) errors.push(`${pointer}.sidecar is duplicated`);
			paths.add(entry.path);
			sidecars.add(entry.sidecar);
			if (previous !== null && compareText(previous, entry.path) >= 0) {
				errors.push("claim_artifacts must be strictly sorted by path");
			}
			previous = entry.path;
		}
	}
	return errors;
}

function loadArtifactManifest(root) {
	const value = readRepoJSON(root, ARTIFACT_MANIFEST_PATH);
	const errors = validateArtifactManifest(value);
	if (errors.length > 0) throw new Error(`${ARTIFACT_MANIFEST_PATH}: ${errors.join("; ")}`);
	return value;
}

function canonicalArtifactManifest(value) {
	return {
		schema_version: ARTIFACT_MANIFEST_SCHEMA_VERSION,
		claim_namespaces: value.claim_namespaces.map((entry) => ({
			namespace: entry.namespace,
			display_name: entry.display_name,
			next_number: entry.next_number,
		})),
		claim_artifacts: value.claim_artifacts.map((entry) => ({
			path: entry.path,
			namespace: entry.namespace,
			sidecar: entry.sidecar,
		})),
	};
}

function formatClaimId(namespace, number) {
	if (!NAMESPACE_PATTERN.test(namespace)) throw new Error(`invalid namespace: ${namespace}`);
	if (!Number.isSafeInteger(number) || number < 1) throw new Error(`invalid claim number: ${number}`);
	return `${namespace}-${String(number).padStart(4, "0")}`;
}

function parseClaimIdForNamespace(id, namespace) {
	if (typeof id !== "string" || !id.startsWith(`${namespace}-`)) return null;
	const digits = id.slice(namespace.length + 1);
	if (!/^\d{4,}$/.test(digits)) return null;
	const number = Number(digits);
	if (!Number.isSafeInteger(number) || number < 1 || formatClaimId(namespace, number) !== id) return null;
	return number;
}

function namespaceForClaimId(id, manifest) {
	for (const entry of [...manifest.claim_namespaces].sort((a, b) => b.namespace.length - a.namespace.length)) {
		const number = parseClaimIdForNamespace(id, entry.namespace);
		if (number !== null) return { entry, number };
	}
	return null;
}

function artifactEntry(manifest, artifactPath) {
	const artifact = manifest.claim_artifacts.find((entry) => entry.path === artifactPath);
	if (!artifact) throw new Error(`artifact is not registered: ${artifactPath}`);
	return artifact;
}

function namespaceEntry(manifest, namespace) {
	const entry = manifest.claim_namespaces.find((candidate) => candidate.namespace === namespace);
	if (!entry) throw new Error(`namespace is not registered: ${namespace}`);
	return entry;
}

function allocateClaimIds(root, artifactPath, count = 1) {
	if (!Number.isSafeInteger(count) || count < 1) throw new Error("count must be a positive safe integer");
	return withClaimContractLock(root, () => {
		const manifest = loadArtifactManifest(root);
		const artifact = artifactEntry(manifest, artifactPath);
		const markdown = safeRegularFile(root, artifact.path);
		if (!markdown.ok) throw new Error(`${artifact.path}: ${markdown.reason}`);
		const namespace = namespaceEntry(manifest, artifact.namespace);
		if (!Number.isSafeInteger(namespace.next_number + count)) throw new Error("claim number overflow");
		const ids = [];
		for (let offset = 0; offset < count; offset += 1) {
			ids.push(formatClaimId(namespace.namespace, namespace.next_number + offset));
		}
		namespace.next_number += count;
		writeRepoJSON(root, ARTIFACT_MANIFEST_PATH, canonicalArtifactManifest(manifest));
		return ids;
	});
}

function validateAllocatedClaimId(manifest, artifact, id) {
	const namespace = namespaceEntry(manifest, artifact.namespace);
	const number = parseClaimIdForNamespace(id, artifact.namespace);
	if (number === null) throw new Error(`${id}: invalid ID for namespace ${artifact.namespace}`);
	if (number >= namespace.next_number) {
		throw new Error(`${id}: ID was not allocated below next_number ${namespace.next_number}`);
	}
	return number;
}

function writeUserConfirmation(root, input) {
	if (!isPlainObject(input)) throw new Error("confirmation input must be an object");
	return withClaimContractLock(root, () => {
		const { ref, confirmed_by: confirmedBy, date, claim_ids: claimIds } = input;
		if (
			!isRepoRelativePath(ref) ||
			!ref.startsWith(`${TRANSCRIPT_DIR}/`) ||
			!ref.endsWith(".json")
		) {
			throw new Error(`confirmation ref must be a JSON path below ${TRANSCRIPT_DIR}`);
		}
		if (!hasNonWhitespace(confirmedBy)) throw new Error("confirmed_by must contain non-whitespace text");
		if (!isCalendarDate(date)) throw new Error("date must be a real YYYY-MM-DD calendar date");
		if (!Array.isArray(claimIds) || claimIds.length === 0) throw new Error("claim_ids must be a non-empty array");
		const manifest = loadArtifactManifest(root);
		const existingRef = safeRegularFile(root, ref);
		if (existingRef.ok) {
			for (const claimArtifact of manifest.claim_artifacts) {
				if (sameFileIdentity(existingRef, safeRegularFile(root, claimArtifact.path))) {
					throw new Error("confirmation ref must differ from every claim-bearing artifact");
				}
			}
		}
		const unique = [...new Set(claimIds)].sort(compareText);
		if (unique.length !== claimIds.length) throw new Error("claim_ids must not contain duplicates");
		for (const id of unique) {
			const parsed = namespaceForClaimId(id, manifest);
			if (!parsed || parsed.number >= parsed.entry.next_number) throw new Error(`${id}: claim ID is not allocated`);
		}
		const record = {
			schema_version: CONFIRMATION_SCHEMA_VERSION,
			confirmed_by: confirmedBy,
			date,
			claim_ids: unique,
		};
		writeImmutableRepoJSON(root, ref, record);
		return record;
	});
}

function readUserConfirmation(root, ref) {
	if (
		!isRepoRelativePath(ref) ||
		!ref.startsWith(`${TRANSCRIPT_DIR}/`) ||
		!ref.endsWith(".json")
	) {
		throw new Error(`must be a JSON path below ${TRANSCRIPT_DIR}`);
	}
	const record = readRepoJSON(root, ref);
	if (!exactKeys(record, ["schema_version", "confirmed_by", "date", "claim_ids"])) {
		throw new Error("confirmation record fields are invalid");
	}
	if (record.schema_version !== CONFIRMATION_SCHEMA_VERSION) throw new Error("confirmation schema_version is invalid");
	if (!hasNonWhitespace(record.confirmed_by)) throw new Error("confirmation confirmed_by is invalid");
	if (!isCalendarDate(record.date)) throw new Error("confirmation date is invalid");
	if (!Array.isArray(record.claim_ids) || record.claim_ids.length === 0) {
		throw new Error("confirmation claim_ids must be non-empty");
	}
	for (let index = 0; index < record.claim_ids.length; index += 1) {
		if (typeof record.claim_ids[index] !== "string") throw new Error("confirmation claim_ids must be strings");
		if (index > 0 && compareText(record.claim_ids[index - 1], record.claim_ids[index]) >= 0) {
			throw new Error("confirmation claim_ids must be strictly sorted");
		}
	}
	return record;
}

function safeConfirmationRef(root, manifest, ref) {
	const file = safeRegularFile(root, ref);
	if (!file.ok) throw new Error(`confirmation ref ${file.reason}`);
	for (const claimArtifact of manifest.claim_artifacts) {
		const markdown = safeRegularFile(root, claimArtifact.path);
		if (sameFileIdentity(file, markdown)) {
			throw new Error("confirmation ref must differ from every claim-bearing artifact");
		}
	}
	return file;
}

function validateConfirmationReference(root, manifest, artifact, claimId, confirmedBy) {
	if (!isPlainObject(confirmedBy)) throw new Error("confirmed_by must be an object");
	if (!exactKeys(confirmedBy, ["type", "ref", "date"])) throw new Error("confirmed_by fields are invalid");
	if (!CONFIRMATION_TYPES.has(confirmedBy.type)) throw new Error("confirmed_by.type is invalid");
	if (!isRepoRelativePath(confirmedBy.ref)) throw new Error("confirmed_by.ref is unsafe");
	if (!isCalendarDate(confirmedBy.date)) throw new Error("confirmed_by.date is invalid");
	safeConfirmationRef(root, manifest, confirmedBy.ref);
	if (confirmedBy.type === "user") {
		const record = readUserConfirmation(root, confirmedBy.ref);
		if (record.date !== confirmedBy.date) throw new Error("confirmation record date does not match");
		if (!record.claim_ids.includes(claimId)) throw new Error(`confirmation record does not cover ${claimId}`);
		for (const id of record.claim_ids) {
			const parsed = namespaceForClaimId(id, manifest);
			if (!parsed || parsed.number >= parsed.entry.next_number) {
				throw new Error(`confirmation record contains unallocated claim ID ${id}`);
			}
		}
		return;
	}
	if (manifest.claim_artifacts.some((entry) => entry.path === confirmedBy.ref)) {
		throw new Error("adr/policy ref must differ from every claim-bearing artifact");
	}
}

function writeClaimSidecar(root, artifactPath, items) {
	if (!Array.isArray(items)) throw new Error("items must be an array");
	return withClaimContractLock(root, () => {
		const manifest = loadArtifactManifest(root);
		const artifact = artifactEntry(manifest, artifactPath);
		const markdown = safeRegularFile(root, artifact.path);
		if (!markdown.ok) throw new Error(`${artifact.path}: ${markdown.reason}`);
		const currentSidecar = safeRegularFile(root, artifact.sidecar);
		const seen = new Set();
		const canonicalItems = [];
		for (const item of items) {
			if (!isPlainObject(item)) throw new Error("claim item must be an object");
			validateAllocatedClaimId(manifest, artifact, item.id);
			if (seen.has(item.id)) throw new Error(`duplicate claim ID: ${item.id}`);
			seen.add(item.id);
			if (item.kind === "observed") {
				if (!exactKeys(item, ["id", "kind", "sources"])) throw new Error(`${item.id}: observed item fields are invalid`);
				if (!Array.isArray(item.sources) || item.sources.length === 0) {
					throw new Error(`${item.id}: observed sources must be non-empty`);
				}
				const paths = [...item.sources];
				if (!paths.every((path) => typeof path === "string")) throw new Error(`${item.id}: source paths must be strings`);
				paths.sort(compareText);
				if (new Set(paths).size !== paths.length) throw new Error(`${item.id}: source paths must be unique`);
				if (
					paths.includes(artifact.sidecar) ||
					paths.some((path) => sameFileIdentity(currentSidecar, safeRegularFile(root, path)))
				) {
					throw new Error(`${item.id}: source must not be its own sidecar`);
				}
				canonicalItems.push({
					id: item.id,
					kind: "observed",
					sources: paths.map((path) => ({ path, sha256: hashRepoFile(root, path) })),
				});
				continue;
			}
			if (item.kind === "intent") {
				if (!exactKeys(item, ["id", "kind", "confirmed_by"])) throw new Error(`${item.id}: intent item fields are invalid`);
				validateConfirmationReference(root, manifest, artifact, item.id, item.confirmed_by);
				canonicalItems.push({
					id: item.id,
					kind: "intent",
					confirmed_by: {
						type: item.confirmed_by.type,
						ref: item.confirmed_by.ref,
						date: item.confirmed_by.date,
					},
				});
				continue;
			}
			throw new Error(`${item.id}: kind must be observed or intent`);
		}
		canonicalItems.sort((left, right) => compareText(left.id, right.id));
		const sidecar = { schema_version: CLAIM_SCHEMA_VERSION, artifact: artifact.path, items: canonicalItems };
		writeRepoJSON(root, artifact.sidecar, sidecar);
		return sidecar;
	});
}

function addViolation(violations, code, path, message) {
	violations.push({ code, path, message });
}

function listClaimJSONFiles(root) {
	const absolute = join(resolve(root), ...CLAIMS_DIR.split("/"));
	if (!existsSync(absolute)) return [];
	const rootInfo = lstatSync(absolute);
	if (rootInfo.isSymbolicLink() || !rootInfo.isDirectory()) {
		return [{ path: CLAIMS_DIR, unsafe: true }];
	}
	const out = [];
	function walk(directory, repoDirectory) {
		const entries = readdirSync(directory, { withFileTypes: true }).sort((a, b) => compareText(a.name, b.name));
		for (const entry of entries) {
			const path = join(directory, entry.name);
			const repoPath = `${repoDirectory}/${entry.name}`;
			if (entry.isSymbolicLink()) {
				out.push({ path: repoPath, unsafe: true });
			} else if (entry.isDirectory()) {
				walk(path, repoPath);
			} else if (entry.isFile() && entry.name.endsWith(".json")) {
				out.push({ path: repoPath, unsafe: false });
			}
		}
	}
	walk(absolute, CLAIMS_DIR);
	return out;
}

function tokenPattern(namespaces) {
	const alternatives = [...namespaces]
		.sort((a, b) => b.length - a.length || compareText(a, b))
		.map((value) => value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"));
	return alternatives.length === 0 ? null : new RegExp(`\\[(${alternatives.join("|")})-(\\d{4,})\\]`, "g");
}

function validateSidecar(root, manifest, artifact, value, violations, state) {
	const base = artifact.sidecar;
	if (!isPlainObject(value)) {
		addViolation(violations, "schema_invalid", base, "sidecar must be an object");
		return;
	}
	for (const key of knownKeys(value, new Set(["schema_version", "artifact", "items"]))) {
		addViolation(violations, "schema_invalid", `${base}#/${key}`, "unknown field");
	}
	if (value.schema_version !== CLAIM_SCHEMA_VERSION) {
		addViolation(violations, "schema_invalid", `${base}#/schema_version`, `must equal ${CLAIM_SCHEMA_VERSION}`);
	}
	if (value.artifact !== artifact.path) {
		addViolation(violations, "artifact_mismatch", `${base}#/artifact`, `must equal ${artifact.path}`);
	}
	if (!Array.isArray(value.items)) {
		addViolation(violations, "schema_invalid", `${base}#/items`, "must be an array");
		return;
	}
	let previousId = null;
	const localIds = new Set();
	for (let index = 0; index < value.items.length; index += 1) {
		const item = value.items[index];
		const pointer = `${base}#/items/${index}`;
		if (!isPlainObject(item)) {
			addViolation(violations, "schema_invalid", pointer, "item must be an object");
			continue;
		}
		const id = item.id;
		if (typeof id === "string") {
			state.sidecarIdsByArtifact.get(artifact.path).add(id);
			const locations = state.sidecarLocations.get(id) || [];
			locations.push(pointer);
			state.sidecarLocations.set(id, locations);
		}
		const number = parseClaimIdForNamespace(id, artifact.namespace);
		if (number === null) {
			addViolation(violations, "claim_id_invalid", `${pointer}/id`, `must use namespace ${artifact.namespace} and canonical numbering`);
		} else {
			const namespace = namespaceEntry(manifest, artifact.namespace);
			if (number >= namespace.next_number) {
				addViolation(
					violations,
					"high_water_invalid",
					`${pointer}/id`,
					`${id} must be below next_number ${namespace.next_number}`,
				);
			}
		}
		if (localIds.has(id)) addViolation(violations, "sidecar_id_duplicate", `${pointer}/id`, `${id} is duplicated`);
		localIds.add(id);
		if (previousId !== null && compareText(previousId, id) >= 0) {
			addViolation(violations, "items_not_sorted", pointer, "items must be strictly sorted by ID");
		}
		previousId = id;
		if (item.kind === "observed") {
			state.counts.observed += 1;
			for (const key of knownKeys(item, new Set(["id", "kind", "sources"]))) {
				addViolation(violations, "schema_invalid", `${pointer}/${key}`, "unknown field");
			}
			if (!Array.isArray(item.sources) || item.sources.length === 0) {
				addViolation(violations, "schema_invalid", `${pointer}/sources`, "observed sources must be non-empty");
				continue;
			}
			let previousPath = null;
			const sourcePaths = new Set();
			for (let sourceIndex = 0; sourceIndex < item.sources.length; sourceIndex += 1) {
				const source = item.sources[sourceIndex];
				const sourcePointer = `${pointer}/sources/${sourceIndex}`;
				if (!isPlainObject(source)) {
					addViolation(violations, "schema_invalid", sourcePointer, "source must be an object");
					continue;
				}
				for (const key of knownKeys(source, new Set(["path", "sha256"]))) {
					addViolation(violations, "schema_invalid", `${sourcePointer}/${key}`, "unknown field");
				}
				if (!isRepoRelativePath(source.path)) {
					addViolation(violations, "source_unsafe", `${sourcePointer}/path`, "source path is unsafe");
				} else {
					if (sourcePaths.has(source.path)) {
						addViolation(violations, "source_duplicate", `${sourcePointer}/path`, `${source.path} is duplicated`);
					}
					sourcePaths.add(source.path);
					if (previousPath !== null && compareText(previousPath, source.path) >= 0) {
						addViolation(violations, "sources_not_sorted", sourcePointer, "sources must be strictly sorted by path");
					}
					previousPath = source.path;
					const file = safeRegularFile(root, source.path);
					if (!file.ok) {
						addViolation(violations, "source_unavailable", source.path, `${id}: ${file.reason}`);
					} else {
						try {
							const actual = sha256FileWithoutFollowingSymlink(file.path);
							if (source.sha256 !== actual) {
								addViolation(violations, "source_hash_mismatch", source.path, `${id}: expected ${source.sha256}, actual ${actual}`);
							}
						} catch {
							addViolation(violations, "source_unavailable", source.path, `${id}: unreadable`);
						}
					}
				}
				if (typeof source.sha256 !== "string" || !SHA256_PATTERN.test(source.sha256)) {
					addViolation(violations, "schema_invalid", `${sourcePointer}/sha256`, "must be lowercase SHA-256 hex");
				}
			}
		} else if (item.kind === "intent") {
			state.counts.intent += 1;
			for (const key of knownKeys(item, new Set(["id", "kind", "confirmed_by"]))) {
				addViolation(violations, "schema_invalid", `${pointer}/${key}`, "unknown field");
			}
			try {
				validateConfirmationReference(root, manifest, artifact, id, item.confirmed_by);
			} catch (error) {
				addViolation(
					violations,
					"confirmation_invalid",
					`${pointer}/confirmed_by`,
					error instanceof Error ? error.message : String(error),
				);
			}
		} else {
			addViolation(violations, "schema_invalid", `${pointer}/kind`, "must be observed or intent");
		}
	}
	state.counts.sidecar_items += value.items.length;
}

function verifyClaims(root = process.cwd()) {
	const violations = [];
	const counts = {
		namespaces: 0,
		artifacts: 0,
		markdown_tokens: 0,
		sidecar_items: 0,
		observed: 0,
		intent: 0,
	};
	let manifest;
	try {
		manifest = loadArtifactManifest(root);
	} catch (error) {
		addViolation(
			violations,
			"manifest_invalid",
			ARTIFACT_MANIFEST_PATH,
			error instanceof Error ? error.message : String(error),
		);
		return buildReport(counts, violations);
	}
	counts.namespaces = manifest.claim_namespaces.length;
	counts.artifacts = manifest.claim_artifacts.length;
	const mappedSidecars = new Set(manifest.claim_artifacts.map((entry) => entry.sidecar));
	let claimFiles = [];
	try {
		claimFiles = listClaimJSONFiles(root);
	} catch {
		addViolation(violations, "sidecar_scan_failed", CLAIMS_DIR, "claim sidecar directory is unreadable");
	}
	for (const entry of claimFiles) {
		if (entry.unsafe) addViolation(violations, "sidecar_unsafe", entry.path, "symlink is not allowed");
		else if (!mappedSidecars.has(entry.path)) addViolation(violations, "sidecar_unmapped", entry.path, "sidecar is not registered");
	}
	const namespaces = manifest.claim_namespaces.map((entry) => entry.namespace);
	const pattern = tokenPattern(namespaces);
	const state = {
		counts,
		markdownIdsByArtifact: new Map(),
		markdownLocations: new Map(),
		sidecarIdsByArtifact: new Map(),
		sidecarLocations: new Map(),
	};
	for (const artifact of manifest.claim_artifacts) {
		const markdownIds = new Set();
		const sidecarIds = new Set();
		state.markdownIdsByArtifact.set(artifact.path, markdownIds);
		state.sidecarIdsByArtifact.set(artifact.path, sidecarIds);
		const markdown = safeRegularFile(root, artifact.path);
		if (!markdown.ok) {
			addViolation(violations, "artifact_unavailable", artifact.path, markdown.reason);
		} else if (pattern) {
			let contents;
			try {
				contents = readFileWithoutFollowingSymlink(markdown.path).toString("utf8");
			} catch {
				addViolation(violations, "artifact_unavailable", artifact.path, "unreadable");
				contents = null;
			}
			if (contents !== null) {
				pattern.lastIndex = 0;
				let match;
				while ((match = pattern.exec(contents)) !== null) {
					const id = `${match[1]}-${match[2]}`;
					counts.markdown_tokens += 1;
					markdownIds.add(id);
					const locations = state.markdownLocations.get(id) || [];
					locations.push(`${artifact.path}:${match.index}`);
					state.markdownLocations.set(id, locations);
					const parsed = parseClaimIdForNamespace(id, match[1]);
					if (parsed === null) {
						addViolation(violations, "claim_id_invalid", artifact.path, `${id} is not canonically numbered`);
					}
					if (match[1] !== artifact.namespace) {
						addViolation(
							violations,
							"markdown_namespace_mismatch",
							artifact.path,
							`${id} belongs to ${match[1]}, expected ${artifact.namespace}`,
						);
					}
				}
			}
		}
		let sidecar;
		try {
			sidecar = readRepoJSON(root, artifact.sidecar);
		} catch (error) {
			addViolation(
				violations,
				"sidecar_unavailable",
				artifact.sidecar,
				error instanceof Error ? error.message : String(error),
			);
			continue;
		}
		validateSidecar(root, manifest, artifact, sidecar, violations, state);
	}
	for (const [id, locations] of state.markdownLocations) {
		if (locations.length > 1) addViolation(violations, "markdown_id_duplicate", locations[1], `${id} appears ${locations.length} times`);
	}
	for (const [id, locations] of state.sidecarLocations) {
		if (locations.length > 1) addViolation(violations, "sidecar_id_duplicate", locations[1], `${id} appears ${locations.length} times`);
	}
	for (const artifact of manifest.claim_artifacts) {
		const markdownIds = state.markdownIdsByArtifact.get(artifact.path);
		const sidecarIds = state.sidecarIdsByArtifact.get(artifact.path);
		for (const id of [...markdownIds].sort(compareText)) {
			if (!sidecarIds.has(id)) addViolation(violations, "sidecar_item_missing", artifact.sidecar, `${id} exists only in Markdown`);
		}
		for (const id of [...sidecarIds].sort(compareText)) {
			if (!markdownIds.has(id)) addViolation(violations, "markdown_token_missing", artifact.path, `${id} exists only in sidecar`);
		}
	}
	return buildReport(counts, violations);
}

function buildReport(counts, violations) {
	violations.sort(
		(left, right) =>
			compareText(left.path, right.path) || compareText(left.code, right.code) || compareText(left.message, right.message),
	);
	return {
		schema_version: REPORT_SCHEMA_VERSION,
		claim_schema: { name: CLAIM_SCHEMA_NAME, version: CLAIM_SCHEMA_VERSION },
		status: violations.length === 0 ? "passed" : "failed",
		valid: violations.length === 0,
		counts,
		violations,
	};
}

function optionValue(args, name, { multiple = false } = {}) {
	const values = [];
	for (let index = 0; index < args.length; index += 1) {
		if (args[index] !== name) continue;
		if (!args[index + 1] || args[index + 1].startsWith("--")) throw new Error(`${name} requires a value`);
		values.push(args[index + 1]);
		index += 1;
	}
	if (multiple) return values;
	if (values.length > 1) throw new Error(`${name} may be provided only once`);
	return values[0];
}

function assertKnownOptions(args, options) {
	for (let index = 0; index < args.length; index += 1) {
		const arg = args[index];
		if (!arg.startsWith("--") || !options.has(arg)) throw new Error(`unknown argument: ${arg}`);
		if (arg === "--json") continue;
		index += 1;
	}
}

function usage() {
	return [
		"Usage:",
		"  node scripts/claims-verify.cjs [verify] [--json] [--root <repo>]",
		"  node scripts/claims-verify.cjs allocate --artifact <path> [--count <n>] [--root <repo>]",
		"  node scripts/claims-verify.cjs hash --path <path> [--root <repo>]",
		"  node scripts/claims-verify.cjs confirm-user --ref <path> --confirmed-by <name> --date <YYYY-MM-DD> --claim <id> [--claim <id> ...] [--root <repo>]",
		"  node scripts/claims-verify.cjs write-sidecar --artifact <path> --input <repo-json-path> [--root <repo>]",
		"",
		"Verification exits 0 only when every registered Claim contract check passes; all violations exit 1.",
	].join("\n");
}

function main(argv = process.argv.slice(2)) {
	if (argv.includes("--help") || argv.includes("-h")) {
		process.stdout.write(`${usage()}\n`);
		return;
	}
	let command = "verify";
	let args = argv;
	if (args[0] && !args[0].startsWith("--")) {
		command = args[0];
		args = args.slice(1);
	}
	const root = resolve(optionValue(args, "--root") || process.cwd());
	if (command === "verify") {
		assertKnownOptions(args, new Set(["--json", "--root"]));
		const report = verifyClaims(root);
		if (args.includes("--json")) process.stdout.write(canonicalJSONStringify(report));
		else {
			process.stdout.write(`Claim verification ${report.status}: ${report.violations.length} violation(s)\n`);
			for (const violation of report.violations) {
				process.stdout.write(`- [${violation.code}] ${violation.path}: ${violation.message}\n`);
			}
		}
		process.exitCode = report.valid ? 0 : 1;
		return;
	}
	if (command === "allocate") {
		assertKnownOptions(args, new Set(["--artifact", "--count", "--root"]));
		const artifact = optionValue(args, "--artifact");
		if (!artifact) throw new Error("--artifact is required");
		const countText = optionValue(args, "--count") || "1";
		if (!/^\d+$/.test(countText)) throw new Error("--count must be a positive integer");
		process.stdout.write(canonicalJSONStringify({ ids: allocateClaimIds(root, artifact, Number(countText)) }));
		return;
	}
	if (command === "hash") {
		assertKnownOptions(args, new Set(["--path", "--root"]));
		const path = optionValue(args, "--path");
		if (!path) throw new Error("--path is required");
		process.stdout.write(canonicalJSONStringify({ path, sha256: hashRepoFile(root, path) }));
		return;
	}
	if (command === "confirm-user") {
		assertKnownOptions(args, new Set(["--ref", "--confirmed-by", "--date", "--claim", "--root"]));
		const claimIds = optionValue(args, "--claim", { multiple: true });
		const record = writeUserConfirmation(root, {
			ref: optionValue(args, "--ref"),
			confirmed_by: optionValue(args, "--confirmed-by"),
			date: optionValue(args, "--date"),
			claim_ids: claimIds,
		});
		process.stdout.write(canonicalJSONStringify(record));
		return;
	}
	if (command === "write-sidecar") {
		assertKnownOptions(args, new Set(["--artifact", "--input", "--root"]));
		const artifact = optionValue(args, "--artifact");
		const input = optionValue(args, "--input");
		if (!artifact || !input) throw new Error("--artifact and --input are required");
		const draft = readRepoJSON(root, input);
		const items = Array.isArray(draft) ? draft : draft.items;
		process.stdout.write(canonicalJSONStringify(writeClaimSidecar(root, artifact, items)));
		return;
	}
	throw new Error(`unknown command: ${command}`);
}

module.exports = {
	ARTIFACT_MANIFEST_SCHEMA_VERSION,
	CLAIM_SCHEMA_VERSION,
	allocateClaimIds,
	canonicalJSONStringify,
	formatClaimId,
	hashRepoFile,
	isRepoRelativePath,
	loadArtifactManifest,
	verifyClaims,
	writeClaimSidecar,
	writeUserConfirmation,
};

if (require.main === module) {
	try {
		main();
	} catch (error) {
		const argv = process.argv.slice(2);
		const machineVerify = argv.includes("--json") && (!argv[0] || argv[0] === "verify" || argv[0].startsWith("--"));
		if (machineVerify) {
			const code = error && typeof error === "object" && "code" in error ? ` (${error.code})` : "";
			const report = buildReport(
				{ namespaces: 0, artifacts: 0, markdown_tokens: 0, sidecar_items: 0, observed: 0, intent: 0 },
				[{ code: "internal_error", path: ".", message: `unexpected verification failure${code}` }],
			);
			process.stdout.write(canonicalJSONStringify(report));
		} else {
			process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
		}
		process.exitCode = 1;
	}
}
