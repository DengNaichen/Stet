import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtemp, readFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";

import { materializeInitTemplates } from "./init-materialize.mjs";

const harnesskitRoot = join(dirname(fileURLToPath(import.meta.url)), "..");
const skillPath = join(
	harnesskitRoot,
	"skills",
	"harnesskit-fill-interaction-design",
	"SKILL.md",
);
const agentPath = join(
	harnesskitRoot,
	"skills",
	"harnesskit-fill-interaction-design",
	"agents",
	"harness-agent.yaml",
);
const manifestPath = join(
	harnesskitRoot,
	"templates",
	"profiles",
	"web-frontend",
	".harnesskit",
	"audit",
	"artifact-manifest.json",
);

async function read(path) {
	return readFile(path, "utf8");
}

function section(markdown, heading) {
	const start = markdown.indexOf(heading);
	assert.notEqual(start, -1, `missing section: ${heading}`);
	const next = markdown.indexOf("\n## ", start + heading.length);
	return markdown.slice(start, next === -1 ? markdown.length : next);
}

function assertInOrder(contents, snippets) {
	let offset = 0;
	for (const snippet of snippets) {
		const index = contents.indexOf(snippet, offset);
		assert.notEqual(index, -1, `missing or out-of-order text: ${snippet}`);
		offset = index + snippet.length;
	}
}

function sealingExample(markdown) {
	const workflow = section(markdown, "## Markdown-first workflow");
	const block = /```sh\n(   node scripts\/claims-verify\.cjs write-sidecar --artifact "docs\/INTERACTION_DESIGN\.md" --stdin <<'JSON'\n[\s\S]*?\n   JSON)\n   ```/.exec(
		workflow,
	);
	assert.ok(block, "missing executable write-sidecar example");
	const script = block[1].replace(/^ {3}/gm, "");
	const payload = /<<'JSON'\n([\s\S]*?)\nJSON$/.exec(script);
	assert.ok(payload, "missing write-sidecar JSON stdin payload");
	return { script, payload: JSON.parse(payload[1]) };
}

test("owns only the registered Interaction Design Claim contract", async () => {
	const [skill, agent, manifestBytes] = await Promise.all([
		read(skillPath),
		read(agentPath),
		read(manifestPath),
	]);
	const manifest = JSON.parse(manifestBytes);

	assert.deepEqual(
		manifest.claim_artifacts.find(({ path }) => path === "docs/INTERACTION_DESIGN.md"),
		{
			path: "docs/INTERACTION_DESIGN.md",
			namespace: "INTERACTION-DESIGN",
			sidecar: ".harnesskit/audit/claims/docs-INTERACTION_DESIGN.json",
		},
	);
	assert.deepEqual(
		manifest.claim_namespaces.find(({ namespace }) => namespace === "INTERACTION-DESIGN"),
		{ namespace: "INTERACTION-DESIGN", display_name: "Interaction design", next_number: 1 },
	);
	assert.match(skill, /唯一 artifact `docs\/INTERACTION_DESIGN\.md`/);
	assert.match(skill, /namespace `INTERACTION-DESIGN`/);
	assert.match(skill, /sidecar `\.harnesskit\/audit\/claims\/docs-INTERACTION_DESIGN\.json`/);
	assertInOrder(skill, [
		"不创建或修改 profile materialize",
		"不处理 root/part",
		"不把本 artifact 提升为 canonical",
	]);
	assert.match(agent, /display_name: "生成 Interaction Design Claims"/);
	assert.match(agent, /default_prompt: "使用 \$harnesskit-fill-interaction-design /);
});

test("keeps scan review and intent rounds artifact-scoped", async () => {
	const skill = await read(skillPath);
	const rounds = section(skill, "## 本份轮次");
	const scanReview = section(skill, "## Bootstrap 扫描核对");
	const workflow = section(skill, "## Markdown-first workflow");

	assert.match(rounds, /只声明属于 `docs\/INTERACTION_DESIGN\.md`/);
	assertInOrder(rounds, ["每轮至多 8 题", "本份溢出轮", "不得混入其他 artifact"]);
	assert.match(rounds, /输出 `needs_input` 后停止 repository 读写/);
	assertInOrder(scanReview, ["至多一道", "claim.rows"]);
	assertInOrder(scanReview, ["仍是", "`observed`", "不得写 `confirm-user`"]);
	assertInOrder(scanReview, [
		"整组被否定时丢弃当前 artifact",
		"全部 observed drafts",
		"退休这些 IDs",
		"重扫整个当前 artifact",
		"不再发第二道扫描核对",
	]);
	assert.match(scanReview, /扫描核对解决或跳过后再写入 observed/);
	assertInOrder(workflow, [
		"Bootstrap 先保留",
		"drafts",
		"核对解决或跳过前不得写入 target",
	]);
	assertInOrder(workflow, ["Adopt 保持原流程", "Adopt 跳过此步"]);
});

test("requires repository evidence, atomic Claims, allocation, and deterministic provenance", async () => {
	const skill = await read(skillPath);
	const scan = section(skill, "## 最低扫描面");
	const intent = section(skill, "## Intent 问题发现");
	const workflow = section(skill, "## Markdown-first workflow");
	const boundaries = section(skill, "## 边界");

	assertInOrder(scan, ["navigation", "back", "transitions", "context preservation"]);
	assertInOrder(scan, ["form validation", "submission", "dirty", "leave protection"]);
	assertInOrder(scan, ["overlay", "enter", "exit", "focus", "close"]);
	assertInOrder(scan, ["loading", "empty", "error", "success", "progress"]);
	assertInOrder(scan, ["optimistic", "undo", "destructive confirmation"]);
	assertInOrder(scan, ["keyboard", "pointer", "touch", "focus"]);
	assert.match(scan, /responsive behavior changes/);
	assert.match(intent, /repository signal → repo-native anchors → 未决判断 → 未来影响 → semantic owner → 完整推荐 statement/);
	assert.match(intent, /atomic、bounded/);
	assert.match(intent, /通用性测试/);
	assertInOrder(intent, ["当前实现", "只能触发", "不能自行确认"]);
	assertInOrder(workflow, ["observed", "最小安全 repo-relative sources"]);
	assertInOrder(workflow, ["intent", "独立且权威", "真实用户确认"]);
	assertInOrder(workflow, ["用户自由文本", "不直接成为 evidence"]);
	assert.match(
		workflow,
		/node scripts\/claims-verify\.cjs allocate --artifact "docs\/INTERACTION_DESIGN\.md" --count 1/,
	);
	assert.match(
		workflow,
		/node scripts\/claims-verify\.cjs write-sidecar --artifact "docs\/INTERACTION_DESIGN\.md" --stdin/,
	);
	const example = sealingExample(skill);
	assert.deepEqual(example.payload, { items: [] });
	const target = await mkdtemp(join(tmpdir(), "harnesskit-interaction-owner-contract-"));
	await materializeInitTemplates({ target, profile: "web-frontend" });
	const allocation = spawnSync(
		process.execPath,
		[
			"scripts/claims-verify.cjs",
			"allocate",
			"--artifact",
			"docs/INTERACTION_DESIGN.md",
			"--count",
			"1",
		],
		{ cwd: target, encoding: "utf8" },
	);
	assert.equal(allocation.status, 0, allocation.stderr);
	assert.deepEqual(JSON.parse(allocation.stdout), { ids: ["INTERACTION-DESIGN-0001"] });
	const result = spawnSync("/bin/sh", ["-c", example.script], {
		cwd: target,
		encoding: "utf8",
	});
	assert.equal(result.status, 0, result.stderr);
	assert.deepEqual(JSON.parse(result.stdout), {
		schema_version: 4,
		artifact: "docs/INTERACTION_DESIGN.md",
		items: [],
	});
	assert.match(workflow, /完整 tracked inventory/);
	assert.match(workflow, /node scripts\/claims-verify\.cjs verify --json/);
	assert.match(boundaries, /不计算 ID、SHA-256、JSON ordering，不手写最终 sidecar/);
	assert.match(boundaries, /不得手工编辑 manifest counter，只有 allocation tooling 可更新/);
	assert.doesNotMatch(boundaries, /不修改[^；。\n]*manifest counter/);
});

test("routes non-interaction ownership away from Interaction Design", async () => {
	const skill = await read(skillPath);
	const owner = section(skill, "## Owner");

	assert.match(owner, /token、theme、component variant、size、state 与 visual primitive 归 Design System/);
	assert.match(owner, /路径、依赖与数据流归 Architecture/);
	assert.match(owner, /实现约定归 Coding/);
	assert.match(owner, /产品理由归 Product Sense/);
	assert.match(owner, /cache、retry、cancel 与 state consistency 归 Reliability/);
	assert.match(owner, /trust、input、storage 与 output 归 Security/);
	assert.match(owner, /checks 归 Validation/);
	assertInOrder(owner, ["视觉外观", "不记录行为触发、转换或结果"]);
});

test("leaves unsupported interaction guidance unknown without generic defaults", async () => {
	const skill = await read(skillPath);
	const evidence = section(skill, "## 证据不足");

	assertInOrder(evidence, ["证据不足", "`unknown`"]);
	assert.match(evidence, /只询问本 artifact 必要确认/);
	assert.match(evidence, /不得用通用前端建议补白/);
	assert.match(evidence, /不设置 Claim 数量、问题数量或篇幅配额/);
	assert.doesNotMatch(skill, /默认采用 (?:optimistic|toast|modal|mobile-first|WCAG|ARIA)/i);
});
