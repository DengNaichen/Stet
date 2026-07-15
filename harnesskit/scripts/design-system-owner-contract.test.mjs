import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";

const harnesskitRoot = join(dirname(fileURLToPath(import.meta.url)), "..");
const skillPath = join(
	harnesskitRoot,
	"skills",
	"harnesskit-fill-design-system",
	"SKILL.md",
);
const agentPath = join(
	harnesskitRoot,
	"skills",
	"harnesskit-fill-design-system",
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

test("owns only the registered Design System Claim contract", async () => {
	const [skill, agent, manifestBytes] = await Promise.all([
		read(skillPath),
		read(agentPath),
		read(manifestPath),
	]);
	const manifest = JSON.parse(manifestBytes);

	assert.deepEqual(
		manifest.claim_artifacts.find(({ path }) => path === "docs/DESIGN_SYSTEM.md"),
		{
			path: "docs/DESIGN_SYSTEM.md",
			namespace: "DESIGN-SYSTEM",
			sidecar: ".harnesskit/audit/claims/docs-DESIGN_SYSTEM.json",
		},
	);
	assert.deepEqual(
		manifest.claim_namespaces.find(({ namespace }) => namespace === "DESIGN-SYSTEM"),
		{ namespace: "DESIGN-SYSTEM", display_name: "Design system", next_number: 1 },
	);
	assert.match(skill, /唯一 artifact `docs\/DESIGN_SYSTEM\.md`/);
	assert.match(skill, /namespace `DESIGN-SYSTEM`/);
	assert.match(skill, /sidecar `\.harnesskit\/audit\/claims\/docs-DESIGN_SYSTEM\.json`/);
	assertInOrder(skill, [
		"不创建或修改 profile materialize",
		"不处理 root/part",
		"不把本 artifact 提升为 canonical",
	]);
	assert.match(agent, /display_name: "生成 Design System Claims"/);
	assert.match(agent, /default_prompt: "使用 \$harnesskit-fill-design-system /);
});

test("keeps scan review and intent rounds artifact-scoped", async () => {
	const skill = await read(skillPath);
	const rounds = section(skill, "## 本份轮次");
	const scanReview = section(skill, "## Bootstrap 扫描核对");
	const workflow = section(skill, "## Markdown-first workflow");

	assert.match(rounds, /只声明属于 `docs\/DESIGN_SYSTEM\.md`/);
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

test("requires repository evidence, atomic Claims, confirmation, and deterministic provenance", async () => {
	const skill = await read(skillPath);
	const scan = section(skill, "## 最低扫描面");
	const intent = section(skill, "## Intent 问题发现");
	const workflow = section(skill, "## Markdown-first workflow");
	const boundaries = section(skill, "## 边界");

	assert.match(scan, /semantic tokens|语义令牌/);
	assertInOrder(scan, ["排版", "色彩", "间距", "布局", "主题"]);
	assert.match(scan, /responsive primitives|响应式原语/);
	assertInOrder(scan, ["variants", "sizes", "states", "composition"]);
	assertInOrder(scan, ["icons", "motion"]);
	assert.match(scan, /组件级 accessibility invariants/);
	assert.match(intent, /repository signal → repo-native anchors → 未决判断 → 未来影响 → semantic owner → 完整推荐 statement/);
	assert.match(intent, /atomic、bounded/);
	assert.match(intent, /通用性测试/);
	assertInOrder(intent, ["当前实现", "只能触发", "不能自行确认"]);
	assertInOrder(workflow, ["observed", "最小安全 repo-relative sources"]);
	assertInOrder(workflow, ["intent", "独立且权威", "真实用户确认"]);
	assertInOrder(workflow, ["用户自由文本", "不直接成为 evidence"]);
	assert.match(
		workflow,
		/node scripts\/claims-verify\.cjs allocate --artifact "docs\/DESIGN_SYSTEM\.md" --count 1/,
	);
	assert.match(
		workflow,
		/node scripts\/claims-verify\.cjs write-sidecar --artifact "docs\/DESIGN_SYSTEM\.md" --stdin/,
	);
	assert.match(workflow, /完整 tracked inventory/);
	assert.match(workflow, /node scripts\/claims-verify\.cjs verify --json/);
	assert.match(boundaries, /不计算 ID、SHA-256、JSON ordering，不手写最终 sidecar/);
});

test("routes non-visual ownership away from Design System", async () => {
	const skill = await read(skillPath);
	const owner = section(skill, "## Owner");

	assert.match(owner, /路径、依赖方向与数据流归 Architecture/);
	assert.match(owner, /实现约定归 Coding/);
	assert.match(owner, /产品理由归 Product Sense/);
	assert.match(owner, /失败与恢复归 Reliability/);
	assert.match(owner, /trust boundary 归 Security/);
	assert.match(owner, /检查命令归 Validation/);
	assert.match(owner, /导航、表单、overlay 与反馈行为归 Interaction Design/);
	assertInOrder(owner, ["视觉状态只记录外观契约", "不记录触发、转换或恢复行为"]);
});

test("leaves unsupported design guidance unknown without generic defaults", async () => {
	const skill = await read(skillPath);
	const evidence = section(skill, "## 证据不足");

	assertInOrder(evidence, ["证据不足", "`unknown`"]);
	assert.match(evidence, /只询问本 artifact 必要确认/);
	assert.match(evidence, /不得用通用前端建议补白/);
	assert.match(evidence, /不设置 Claim 数量、问题数量或篇幅配额/);
	assert.doesNotMatch(skill, /默认采用 (?:8px|mobile-first|WCAG|ARIA|Material)/i);
});
