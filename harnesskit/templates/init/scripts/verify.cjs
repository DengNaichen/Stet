"use strict";

const { spawnSync } = require("node:child_process");
const { existsSync, mkdirSync, readFileSync, writeFileSync } = require("node:fs");
const { join } = require("node:path");

const VALIDATION_CONFIG_PATH = join(".harnesskit", "validation.json");

function parseMode(args) {
	const modeIndex = args.indexOf("--mode");
	if (modeIndex < 0) return "full";
	const mode = args[modeIndex + 1];
	if (!mode) throw new Error("Missing value for --mode");
	return mode;
}

function formatCommand(command) {
	return command.join(" ");
}

function createRunId(date) {
	return date.toISOString().replaceAll(/[-:.]/g, "").replace("T", "-").replace("Z", "");
}

function writeReceipt(receipt) {
	const receiptsDir = join(process.cwd(), ".harnesskit", "receipts");
	const runsDir = join(receiptsDir, "runs");
	mkdirSync(runsDir, { recursive: true });
	const serialized = `${JSON.stringify(receipt, null, 2)}\n`;
	writeFileSync(join(receiptsDir, "latest.json"), serialized, "utf-8");
	writeFileSync(join(runsDir, `${receipt.run_id}.json`), serialized, "utf-8");
}

function loadConfig() {
	const configPath = join(process.cwd(), VALIDATION_CONFIG_PATH);
	if (!existsSync(configPath)) {
		return { checks: [] };
	}

	const config = JSON.parse(readFileSync(configPath, "utf-8"));
	if (!config || typeof config !== "object" || !Array.isArray(config.checks)) {
		throw new Error(`${VALIDATION_CONFIG_PATH} must contain a checks array`);
	}

	return config;
}

function validateCheck(check) {
	if (!check || typeof check !== "object") {
		throw new Error("Validation check must be an object");
	}
	if (typeof check.name !== "string" || check.name.trim() === "") {
		throw new Error("Validation check must include a name");
	}
	if (!Array.isArray(check.command) || check.command.length === 0) {
		throw new Error(`Validation check ${check.name} must include a command array`);
	}
	for (const part of check.command) {
		if (typeof part !== "string" || part.length === 0) {
			throw new Error(`Validation check ${check.name} command must contain only non-empty strings`);
		}
	}
}

function runCheck(check) {
	const startedAt = new Date();
	const result = spawnSync(check.command[0], check.command.slice(1), {
		cwd: process.cwd(),
		stdio: "ignore",
	});
	const finishedAt = new Date();
	const exitCode = result.status ?? 1;
	return {
		name: check.name,
		command: formatCommand(check.command),
		status: exitCode === 0 ? "passed" : "failed",
		exit_code: exitCode,
		started_at: startedAt.toISOString(),
		finished_at: finishedAt.toISOString(),
		duration_ms: finishedAt.getTime() - startedAt.getTime(),
	};
}

function main() {
	const startedAt = new Date();
	const mode = parseMode(process.argv.slice(2));
	const runId = createRunId(startedAt);
	const trigger = process.env.HARNESSKIT_VALIDATION_TRIGGER ?? "manual";
	const config = loadConfig();
	const checksToRun = config.checks;
	for (const check of checksToRun) {
		validateCheck(check);
	}

	if (checksToRun.length === 0) {
		const finishedAt = new Date();
		const receipt = {
			schema_version: 1,
			run_id: runId,
			trigger,
			mode,
			status: "not_configured",
			config_path: VALIDATION_CONFIG_PATH,
			started_at: startedAt.toISOString(),
			finished_at: finishedAt.toISOString(),
			checks: [],
			message: `No repository-confirmed validation checks are configured in ${VALIDATION_CONFIG_PATH}.`,
		};
		writeReceipt(receipt);
		console.log("Validation not configured. Receipt: .harnesskit/receipts/latest.json");
		process.exitCode = 2;
		return;
	}

	const checks = [];
	let status = "passed";
	for (const check of checksToRun) {
		const result = runCheck(check);
		checks.push(result);
		if (result.status === "failed") {
			status = "failed";
			break;
		}
	}

	const finishedAt = new Date();
	const receipt = {
		schema_version: 1,
		run_id: runId,
		trigger,
		mode,
		status,
		config_path: VALIDATION_CONFIG_PATH,
		started_at: startedAt.toISOString(),
		finished_at: finishedAt.toISOString(),
		checks,
	};
	writeReceipt(receipt);
	console.log(`Validation ${status}. Receipt: .harnesskit/receipts/latest.json`);
	process.exitCode = status === "passed" ? 0 : 1;
}

try {
	main();
} catch (error) {
	const message = error instanceof Error ? error.message : String(error);
	console.error(`Validation runner error: ${message}`);
	process.exitCode = 1;
}
