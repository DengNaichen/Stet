import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";

const harnesskitRoot = join(dirname(fileURLToPath(import.meta.url)), "..");
const skillRoot = join(harnesskitRoot, "skills");
const skills = {
	kickoff: "harnesskit-kickoff",
	validation: "harnesskit-fill-validation",
	development: "harnesskit-fill-development",
	architecture: "harnesskit-fill-architecture",
	rules: "harnesskit-fill-rules",
	agents: "harnesskit-fill-agents",
};
const ownerNames = ["validation", "development", "architecture", "rules", "agents"];

async function loadSkills() {
	return Object.fromEntries(
		await Promise.all(
			Object.entries(skills).map(async ([key, name]) => [
				key,
				await readFile(join(skillRoot, name, "SKILL.md"), "utf8"),
			]),
		),
	);
}

function section(markdown, heading) {
	const start = markdown.indexOf(heading);
	assert.notEqual(start, -1, `missing section: ${heading}`);
	const next = markdown.indexOf("\n## ", start + heading.length);
	return markdown.slice(start, next === -1 ? markdown.length : next);
}

const stableIdentityContract = {
	positive:
		/(?:statement )?语义未变时(?:必须|应当|仍)?保留 ID、kind 与(?:已有)? confirmation，只(?:用 deterministic tooling )?刷新 source SHA/,
	reversed:
		/(?:statement )?语义未变时[^。；\n]{0,32}(?:不得|禁止|不应|不再|无需|不)保留 ID/,
};
const replacementIdentityContract = {
	positive:
		/(?:真正的 statement|Statement) replacement \/ split \/ merge 必须退休(?:所有)?被取代(?:的)? ID，通过(?: allocation)? tooling 分配新 ID/,
	reversed:
		/(?:真正的 statement|Statement) replacement \/ split \/ merge[^。；\n]*(?:(?:不得|禁止|不应|不再|无需|不)[^，。；\n]{0,12}退休|(?:不得|禁止|不应|不再|无需|不)[^，。；\n]{0,24}分配新 ID)/,
};
const staleProvenanceContract = {
	positive:
		/并移除(?:不再支持新语义的)? stale provenance；不(?:得)?继承失效 source 或 confirmation/,
	reversed:
		/(?:不得|禁止|不应|不再|无需|不)[^，。；\n]{0,12}移除(?:不再支持新语义的)? stale provenance/,
};
const topologyBlockerContract = {
	positive: /Topology、ID namespace 或 semantic owner 冲突(?:立即|必须|必须立即)?返回 blocker/,
	reversed:
		/Topology、ID namespace 或 semantic owner 冲突[^。；\n]{0,16}(?:不得|禁止|不应|不再|无需|不)返回 blocker/,
};
const directDownstreamContract = {
	positive:
		/只返回当前(?: artifact 的|份)? sealed outcome 与 direct semantic downstream impacts；全局 closure 归 orchestrator/,
	reversed:
		/(?:不得|禁止|不应|不再|无需|不)返回[^。；\n]{0,48}`?direct semantic downstream impacts`?/,
};
const terminalDownstreamContract = {
	positive:
		/AGENTS 只返回本份 sealed outcome，(?:`direct semantic downstream impacts` 必须为空|不得返回 `?direct semantic downstream impacts`?)；全局 closure 归 orchestrator/,
	reversed:
		/AGENTS[^。；\n]*(?<!不)(?<!不得)(?<!禁止)(?<!不应)(?<!不再)(?:产生|返回)(?:[^。；\n]*(?:非空|不为空)[^。；\n]*`?direct semantic downstream impacts`?|[^。；\n]*`?direct semantic downstream impacts`?[^。；\n]*(?:非空|不为空))/,
};
const noUpdateDomainOwnerContract = {
	positive:
		/(?:不(?:新建|新增|建立|建)\s*update-specific domain owner|不建[^。；\n]{1,32}(?:或|、|，)\s*update-specific domain owner)/,
	reversed:
		/(?<!不)(?<!不得)(?<!禁止)(?<!不应)(?<!不再)(?:新建|新增|建立)\s*update-specific domain owner/,
};

function followsContract(text, contract) {
	return contract.positive.test(text) && !contract.reversed.test(text);
}

function assertContract(text, contract, label) {
	assert.match(text, contract.positive, `${label}: missing positive contract`);
	assert.doesNotMatch(text, contract.reversed, `${label}: reversed contract`);
}

test("all six skills expose an explicit Refresh invocation with the frozen common input", async () => {
	const contents = await loadSkills();
	const inputs = [
		"changed paths",
		"affected Claim IDs",
		"verifier diagnostics",
		"Markdown drift classification",
		"sealed upstream outcomes",
	];
	for (const [key, markdown] of Object.entries(contents)) {
		assert.match(markdown.split("\n")[2], /Refresh invocation/, `${key} description`);
		const refresh = section(markdown, "## Refresh invocation");
		assert.match(refresh, new RegExp(`\\$${skills[key]} Refresh`), key);
		assert.match(refresh, /Bootstrap \/ Adopt/, key);
		assert.match(refresh, /独立/, key);
		for (const input of inputs) assert.ok(refresh.includes(`\`${input}\``), `${key}: ${input}`);
	}
});

test("artifact owners keep Refresh local and apply the four-way admission matrix", async () => {
	const contents = await loadSkills();
	for (const key of ownerNames) {
		const refresh = section(contents[key], "## Refresh invocation");
		for (const classification of [
			"provenance-only",
			"observed semantic change",
			"new/changed intent",
			"manual Markdown",
		]) {
			assert.ok(refresh.includes(`\`${classification}\``), `${key}: ${classification}`);
		}
		assert.match(refresh, /完整(?:已有 )?(?:tracked )?inventory/, key);
		assert.match(refresh, /最小[\s\S]*证据集/, key);
		assert.match(refresh, /Provenance-only 不提问/, key);
		assert.match(refresh, /observed[\s\S]*至多一[道个][\s\S]*batch review/i, key);
		assert.match(refresh, /(?:intent[\s\S]*逐条独立确认|每条新或变化 intent 独立确认)/i, key);
		assert.match(refresh, /manual Markdown[\s\S]*先询问[\s\S]*修改原因/i, key);
		assert.match(refresh, /(?:问题不得[\s\S]*(?:其他 artifact|跨)|全局 closure 归 orchestrator)/, key);
	}
});

test("stable semantics retain identity while semantic replacement cannot retain stale provenance", async () => {
	const contents = await loadSkills();
	for (const key of ownerNames) {
		const refresh = section(contents[key], "## Refresh invocation");
		assertContract(refresh, stableIdentityContract, `${key}: stable identity`);
		assertContract(refresh, replacementIdentityContract, `${key}: replacement identity`);
		assertContract(refresh, staleProvenanceContract, `${key}: stale provenance`);
		assert.match(refresh, /Markdown-first[\s\S]*完整 inventory[\s\S]*write-sidecar[\s\S]*整份 rewrite/, key);
		assertContract(refresh, topologyBlockerContract, `${key}: topology blocker`);
		assertContract(
			refresh,
			key === "agents" ? terminalDownstreamContract : directDownstreamContract,
			`${key}: direct downstream`,
		);
	}
});

test("polarity guards reject reversed contract mutations", () => {
	const fixtures = [
		{
			label: "stable identity",
			contract: stableIdentityContract,
			positive: "语义未变时保留 ID、kind 与 confirmation，只刷新 source SHA。",
			mutations: ["语义未变时不得保留 ID、kind 与 confirmation，只刷新 source SHA。"],
		},
		{
			label: "replacement identity",
			contract: replacementIdentityContract,
			positive:
				"Statement replacement / split / merge 必须退休被取代 ID，通过 tooling 分配新 ID。",
			mutations: [
				"Statement replacement / split / merge 不得退休被取代 ID，通过 tooling 分配新 ID。",
				"Statement replacement / split / merge 必须退休被取代 ID，不得分配新 ID。",
			],
		},
		{
			label: "stale provenance",
			contract: staleProvenanceContract,
			positive: "并移除 stale provenance；不继承失效 source 或 confirmation。",
			mutations: ["不得移除 stale provenance；不继承失效 source 或 confirmation。"],
		},
		{
			label: "topology blocker",
			contract: topologyBlockerContract,
			positive: "Topology、ID namespace 或 semantic owner 冲突返回 blocker。",
			mutations: ["Topology、ID namespace 或 semantic owner 冲突不得返回 blocker。"],
		},
		{
			label: "direct downstream",
			contract: directDownstreamContract,
			positive:
				"只返回当前 sealed outcome 与 direct semantic downstream impacts；全局 closure 归 orchestrator。",
			mutations: [
				"只返回当前 sealed outcome；不得返回 direct semantic downstream impacts；全局 closure 归 orchestrator。",
			],
		},
		{
			label: "terminal empty direct downstream",
			contract: terminalDownstreamContract,
			positive:
				"AGENTS 只返回本份 sealed outcome，`direct semantic downstream impacts` 必须为空；全局 closure 归 orchestrator。",
			mutations: [
				"AGENTS 只返回本份 sealed outcome，并返回非空 `direct semantic downstream impacts`；全局 closure 归 orchestrator。",
				"AGENTS 产生 `direct semantic downstream impacts` 且不为空；全局 closure 归 orchestrator。",
			],
		},
		{
			label: "terminal omitted direct downstream",
			contract: terminalDownstreamContract,
			positive:
				"AGENTS 只返回本份 sealed outcome，不得返回 `direct semantic downstream impacts`；全局 closure 归 orchestrator。",
			mutations: [],
		},
		{
			label: "direct update-specific owner denial",
			contract: noUpdateDomainOwnerContract,
			positive: "不新建 update-specific domain owner。",
			mutations: [
				"新建 update-specific domain owner。",
				"新增 update-specific domain owner。",
				"建立 update-specific domain owner。",
			],
		},
		{
			label: "coordinated update-specific owner denial",
			contract: noUpdateDomainOwnerContract,
			positive: "不建全局问题池或 update-specific domain owner。",
			mutations: ["不建全局问题池并建立 update-specific domain owner。"],
		},
	];

	for (const { label, contract, positive, mutations } of fixtures) {
		assert.equal(followsContract(positive, contract), true, `${label}: positive fixture`);
		for (const mutation of mutations) {
			assert.equal(contract.reversed.test(mutation), true, `${label}: reversed guard`);
			assert.equal(followsContract(mutation, contract), false, `${label}: ${mutation}`);
		}
	}
});

test("kickoff Refresh is compressed, high-impact only, and never becomes an artifact owner", async () => {
	const { kickoff } = await loadSkills();
	const refresh = section(kickoff, "## Refresh invocation");
	for (const surface of [
		"workspace / project manifest",
		"CI binding",
		"README / project identity",
		"entrypoint",
		"repo shape",
		"part roots",
	]) {
		assert.ok(refresh.includes(surface), surface);
	}
	assert.match(refresh, /只当[\s\S]*高影响 surface[\s\S]*compressed kickoff/);
	assert.match(refresh, /否则原样返回已封存地图且不扫描/);
	assert.match(refresh, /只返回[\s\S]*artifact map[\s\S]*plan brief[\s\S]*直接受影响 owner/);
	assert.match(refresh, /不产出 artifact-specific candidates、Claims、Markdown、sidecar/);
	assert.match(refresh, /Design System[\s\S]*Interaction Design[\s\S]*原唯一 owner/);
	assertContract(refresh, noUpdateDomainOwnerContract, "kickoff: update-specific owner");
	assert.doesNotMatch(refresh, /scan-facts|Facts-Practices/);
});

test("rules stay one-at-a-time and AGENTS consumes sealed upstream outcomes last", async () => {
	const { rules, agents } = await loadSkills();
	const rulesRefresh = section(rules, "## Refresh invocation");
	assert.match(rulesRefresh, /CODING → RELIABILITY → SECURITY → PRODUCT_SENSE/);
	assert.match(rulesRefresh, /一份一份调用[\s\S]*重新封存前不扫描下一份/);
	assert.match(rulesRefresh, /不建 rules-wide 候选池/);
	assert.match(rulesRefresh, /四份 sidecar 永不合并/);

	const agentsRefresh = section(agents, "## Refresh invocation");
	assert.match(agentsRefresh, /最后一份 owner invocation/);
	assert.match(agentsRefresh, /Refresh outcomes 全部 sealed 后才能开始[\s\S]*否则返回 blocker/);
	assert.match(agentsRefresh, /不复制上游正文/);
	assertContract(agentsRefresh, terminalDownstreamContract, "agents: terminal downstream");
});

test("Bootstrap, Adopt, profile routing, and existing owner boundaries remain present", async () => {
	const contents = await loadSkills();
	assert.ok(contents.kickoff.includes("## Bootstrap eligibility preflight"));
	assert.ok(contents.kickoff.includes("## 单仓 Web frontend profile 识别"));
	assert.match(contents.kickoff, /web-frontend[\s\S]*docs\/DESIGN_SYSTEM\.md[\s\S]*docs\/INTERACTION_DESIGN\.md/);
	assert.match(contents.kickoff, /`docs\/DESIGN_SYSTEM\.md` \| semantic token/);
	assert.match(contents.kickoff, /`docs\/INTERACTION_DESIGN\.md` \| 跨功能复用/);
	for (const key of ownerNames) {
		assert.ok(contents[key].includes("## Bootstrap 扫描核对"), `${key}: Bootstrap`);
		assert.ok(contents[key].includes("## Markdown-first workflow"), `${key}: workflow`);
		assert.ok(contents[key].includes("## Bootstrap / Adopt 写入纪律"), `${key}: Adopt`);
		assert.match(contents[key], /Adopt 中未选择的人写 bytes 必须逐字保持/, key);
	}
});

test("Refresh owners do not absorb orchestration, legacy models, or new domains", async () => {
	const contents = await loadSkills();
	for (const [key, markdown] of Object.entries(contents)) {
		const refresh = section(markdown, "## Refresh invocation");
		assert.doesNotMatch(refresh, /scan-facts|Facts-Practices/, key);
		assert.doesNotMatch(refresh, /Git diff|baseline finalize|checkpoint state|final gates/, key);
		if (key !== "kickoff") {
			assert.match(refresh, /不(?:建|建立)[^。；\n]*全局问题池/, `${key}: global question pool`);
			assertContract(refresh, noUpdateDomainOwnerContract, `${key}: update-specific owner`);
		}
	}
});
