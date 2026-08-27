# MVP 最小设计：评审最短闭环 + 记忆最短链路

> 版本：v0.2 · 2026-08-24（并入[补充卷 §5](../research/landscape-supplement.md) 勘误：工件会话隔离、verdict 三态、hash 完整暂存前提、conformance 类型码、场景名存在性校验）
> 范围：只覆盖 README §4 的 MVP 阶段（2–3 周，5–10 人试点）。上游设计见 `ai-native-dev-memory-architecture.md`（下称架构文档），本文档不重复论证，只给可实施的最小契约。
> 目标形态：Claude Code 生态内的 skill/plugin（报告一 §6.2 形态 A 先行），确定性逻辑全部沉淀为与宿主无关的 shell/SQLite 组件。

---

## 0. 做什么、不做什么

**做（4 个组件）**：

1. `review-gate`：pre-commit 门禁脚本（hook + 工件校验）
2. `reviewer`：评审 subagent 的 prompt 模板与派发命令
3. `memoryd`：记忆最短链路（SQLite 单文件 + 提炼 + 审核队列 + 注入）
4. `/sdd-review` 命令：把三者挂进 OpenSpec 工作流

**不做（MVP 明确排除）**：失效引擎、session 综合写入、coding 侧注入、severity 自动路由、A2A、CI 集成、多宿主适配、向量检索。

## 1. 目录结构

```
agent-reviewer/
├── commands/
│   └── sdd-review.md            # /sdd-review 命令（派发 reviewer）
├── agents/
│   └── task-reviewer.md         # reviewer subagent 定义
├── hooks/
│   └── pre-commit-gate.sh       # PreToolUse hook：拦截 git commit
├── rules/
│   ├── registry.json            # 派生物：由 scenarios/*/SKILL.md frontmatter 生成（§2.4）
│   └── scenarios/               # 场景库：每场景一个目录，SKILL.md + cases/（§2.4.1）
├── scripts/
│   ├── review-package.sh        # 打包 diff + spec + 场景规则 + 记忆 → 评审输入
│   ├── verify-artifact.sh       # 校验评审工件（hash + verdict）
│   ├── memory-propose.sh        # 评审结论 → quarantine
│   ├── memory-approve.sh        # 审核通过/驳回
│   └── memory-recall.sh         # 按模块召回 active 条目
├── memory/
│   └── team.db                  # SQLite 单文件记忆库（gitignore）
└── templates/
    ├── reviewer-prompt.md       # reviewer prompt 模板（占位符填充）
    └── distiller-prompt.md      # 提炼 prompt 模板
```

## 2. 组件契约

### 2.1 评审工件（`.git/review-gate/<session-id>.json`）

评审通过的唯一凭证，hook 只认它。路径按会话隔离（codex-review 先例，报告一 §4.4）：session id 取自 PreToolUse hook stdin 的 `session_id` 字段，防同仓库并行会话互覆工件；无 session 上下文时回退 `.review/last-review.json`：

```json
{
  "diff_hash": "sha256 of `git diff HEAD` 的规范输出",
  "verdict": "CLEAN | ISSUES_FOUND | ESCALATED",
  "escalated": false,
  "reviewed_at": "ISO8601",
  "reviewer": "task-reviewer",
  "findings": [
    {"file": "src/x.go", "line": 42, "severity": "critical|important|minor",
     "category": "bug|security|...", "scenario": "null-deref|none",
     "type": "MISSING_IMPL|EXTRA_IMPL|SPEC_DEV|DOC_INCON|OUTDATED_DOC|AMBIGUOUS|none",
     "summary": "…", "resolved": true, "ruling": null}
  ],
  "spec_ref": "openspec/changes/<name>/"
}
```

校验规则（`verify-artifact.sh`，纯 shell + sha256sum + jq）：

0. **SARIF 投影**：`scripts/artifact-to-sarif.sh` 把工件投影为 SARIF 2.1.0（`ruleId`=场景键、rules 元数据来自 SKILL frontmatter、`partialFingerprints` 挂 diff_hash、confidence/checklist_item/ruling 进 `properties`）。canonical 工件不变——SARIF 只作展示/交换层：VSCode SARIF Viewer / GitHub code scanning（`upload-sarif`）/ reviewdog 均可直接消费；TP/FP 标注经 `partialFingerprints.findingIndex` 回传 ANDM quarantine（vscode-opencode-flywheel 模式：扩展只保留标注按钮 + 反馈 API，展示交给 SARIF Viewer）
1. 前置：`git diff --quiet` 通过（无 unstaged 残留）——部分 stage 时「评审过的树 ≠ 提交的树」（commit 只提交 index），hash 绑定必须以完整暂存为前提
2. `diff_hash` == 当前 `git diff HEAD | sha256sum`——**评审后代码再动过一个字节即失效**（报告一 §4.3）
3. `verdict == CLEAN`，或所有 findings 均 `resolved: true`，或 `verdict == ESCALATED`（熔断出口：剩余 findings 全部带人工 `ruling`、工件 `escalated: true`——放行但留痕，呼应 superpowers "a silent discard is forbidden"）
4. 工件生成时间 < 24h
5. findings 的 `scenario` 值必须存在于 `rules/registry.json`——防幻觉场景名（G-Research 规则 ID 存在性校验模式，补充卷 §4）

### 2.2 门禁 hook（`hooks/pre-commit-gate.sh`）

挂在 `PreToolUse`（matcher: `Bash`），只拦截含 `git commit` 的命令：

```
放行条件（任一满足即放行）：
  - diff 总行数 < 20
  - diff 只触及 **.md / docs/**（纯文档豁免）
  - kill switch 文件 .review/DISABLED 存在
拦截时：
  - verify-artifact.sh 对当前会话工件（§2.1 路径）校验通过 → 放行
  - 否则 deny，reason 中附带「请运行 /sdd-review」提示
fail-open：脚本自身任何异常 → exit 0 放行
```

### 2.3 reviewer subagent（`agents/task-reviewer.md` + `templates/reviewer-prompt.md`）

- frontmatter 惯例（报告一 §3.4）：`name`、`model: opus`、`description` 写触发场景 + 内嵌对话示例
- **fresh context 派发**（D2）：controller 用 `review-package.sh` 生成输入包，reviewer 不继承实现者会话
- 输入包（`/tmp/review-<ts>/`）：
  ```
  diff.patch                    # git diff HEAD
  context.md                    # 四元组之二、三、四：
                                #   - spec/plan 相关段落（从 openspec/changes/<name>/ 抽取）
                                #   - 命中场景的 checklist（§2.4 registry 按路径确定性路由）
                                #   - memory-recall.sh 按变更文件路径召回的 active 记忆
  ```
- 评审双通道（D3）：conformance（逐条对照 spec/plan）+ correctness（红队视角挑 diff 本身的错）
- 输出纪律（D4）：每条 finding 必须有 `file:line` + 可复现理由；"could be cleaner" 类不收；结论按 0–100 置信度，只报 ≥80
- conformance 类 finding 用固定机器可读类型码：`MISSING_IMPL / EXTRA_IMPL / SPEC_DEV / DOC_INCON / OUTDATED_DOC / AMBIGUOUS`（serpro69 review-spec 模式，补充卷 §2.2）；其中 OUTDATED_DOC 为反向通道（spec 过时于代码）——产出 quarantine 提案而非阻塞 commit
- reviewer 只读：无 Edit/Write 权限（工具白名单）

### 2.4 场景规则库（`rules/`，对接已有场景化评审资产）

团队已沉淀的场景化 prompt/skill（内存泄露、空指针解引用、死锁等）是四元组中的「规则」元。**场景格式采用标准 SKILL.md，但路由保持确定性**——SKILL.md 只是格式不是发现机制，「该跑哪些场景」仍由脚本按 glob 判定，模型不参与选择（D5，OCR 对纯语言驱动评审的三大痛点：覆盖不全/位置漂移/质量不稳定，报告一 §3.5）：

**注册表由 SKILL.md frontmatter 生成**（单一数据源在 skill，不手工维护）：

```
scripts/build-registry.sh          # 扫描 rules/scenarios/*/SKILL.md 的 frontmatter
    ↓ 生成
rules/registry.json（派生物，gitignore 或定期重建）
  {"rules": [{"path": "**/*.{c,cc,cpp}", "scenarios": ["cwe-476", ...]}, ...]}
```

- 每个场景一个目录（`rules/scenarios/<cwe-key>/`），契约见 §2.4.1
- **为什么用 SKILL.md 格式**：① 跨宿主标准（Claude Code/Codex/Cursor 均可加载），V2 多宿主迁移零改动；② 双重使用——管线里被确定性注入之外，开发者也可在交互会话中手动调用单个场景（skill 的 description 自动路由）；③ frontmatter + 正文 + references 的渐进式披露结构比裸 md 规范
- **确定性路由**：`review-package.sh` 按 diff 触及路径匹配场景（读生成的 registry），只把命中场景的 SKILL.md 正文注入 `context.md`；不相关的场景不注入——控制 prompt 长度就是控制误报率（D5）
- **编排分两档**：小 diff（默认）单 reviewer 注入命中场景一次评审；大 diff（V1）每个命中场景派一个独立场景 subagent 并行评审，findings 汇总后过验证 subagent 二次确认（报告一 §3.4 官方 /code-review 模式）
- **severity 挂场景**：确定性高的场景（null-deref、memory-leak）finding 默认 high severity → 阻塞 commit；风格类场景降级为摘要提示——门禁松紧按场景分级，防 review theater（D9）
- **场景库入治理循环**：现有人写场景 prompt 视为 MDE 撰写的 convention，直接 active 入库；之后的双向回喂——场景命中真实缺陷 → 提炼 `incident_pattern` 进 quarantine；场景漏检（缺陷逃逸）→ 提炼**场景 prompt 改进提案**进 quarantine，MDE 审核后更新 `rules/scenarios/`。场景库随评审历史演进，而非静态资产（ANDM 飞轮在规则层的复用）
- **场景即评测基准**：历史真实缺陷案例（各场景的已知命中/漏检）回放 reviewer，得出 per-scenario 的 precision/recall——README §5 北极星 A/B 指标的现成数据基础，也是调场景 prompt 的客观依据（OCR benchmark 驱动调优，报告一 §3.5）
- 口径注意：场景 checklist 写入本仓库前过一遍业务口径，只保留通用技术模式，不含业务内部细节

### 2.4.1 场景定义契约：CWE 键控 + checklist + 回放样本（三元组）

团队按缺陷 benchmark 论文路线建设的 C/C++ 缺陷场景库（对齐 CASTLE / PrimeVul / CVEfixes / Meta CQS 的方法论），在本设计中每个场景是一个目录而非单个 prompt 文件：

```
rules/scenarios/cwe-476-null-deref/
├── SKILL.md            # 标准 skill 格式，frontmatter 即路由与元数据：
│                       #   name: cwe-476-null-deref
│                       #   description: <触发描述，交互调用时由宿主 agent 路由>
│                       #   cwe: 476
│                       #   severity_default: high
│                       #   paths: ["**/*.{c,cc,cpp}"]     # 确定性路由的 glob 来源
│                       #   ---
│                       #   正文 = 注入 reviewer 的检测清单
└── cases/              # 回放基准样本（现有缺陷案例资产直接迁入）
    ├── pos-001/        # 正例：含缺陷
    │   ├── diff.patch          # 「修复前版本 + diff」= 一个待审 PR
    │   └── golden.json         # {cwe_tag, severity, function, 语句级锚点, rationale}
    └── neg-001/        # 负例：同项目非安全改动（测误报率）
        └── diff.patch
```

要点（均有公开文献依据）：

- **场景命名以 CWE 为键**（cwe-476 / cwe-401 / cwe-416 / cwe-787 / cwe-362 / cwe-190…）：标准化、去重、可直接对齐 MITRE Top 25 与外部 benchmark，registry 的 `scenarios` 字段直接用 CWE 键
- **锚点用语句级而非行号**：C/C++ 中一条语句常跨多行，行级标签无语义（SecVulEval 论证）；评估时允许 ±行容差
- **负样本必需**：取同项目非安全 commit 构造「无问题 PR」测 FP 率；不能沿用「未被 patch 触碰 = 安全」的假设（Big-Vul 教训）
- **golden 标注协议**（若需扩充案例时）：双人**盲标**（隐去 CVE 编号/CWE 标签/commit message 安全关键词）+ CWE tag + 函数 + 语句锚点三维一致才入 golden set；分歧项不丢弃，降级为 hard case 子集（修正 Meta CQS 自报的三个偏差：ground truth 由被测模型生成、标注者可见来源、只验不找漏）
- **防训练集泄漏**：样本优先取 2023 年后的 CVE（晚于主流模型训练截止日），dev/test 按 commit 时间序切分；归一化去重（PrimeVul 实证：现有数据集标签正确率仅 24%~60%，泄漏率最高 18.9%——自建资产的标注质量就是核心竞争力）

### 2.4.2 场景回放评估（`scripts/scenario-replay.sh`，V1 前移到 MVP 后段）

- **两层匹配协议**（Meta CQS）：CWE tag 精确匹配 → 语句锚点/函数规则匹配 → rationale 用固定版本的轻量 judge 模型语义判等；judge 版本写入结果元数据（防漂移导致历史分数不可比）
- **指标**：per-scenario（per-CWE）分层报告 precision/recall/F1——聚合分会掩盖场景间能力方差；另报「限定 FP 率下的漏报率」（对门禁落地更有决策价值）
- **静态分析器基线**：回放时同跑 Clang SA / Infer / Semgrep 作参照系——LLM 评审分数只有对照静态分析基线才可解读；CWE 规则类缺陷未来可评估迁移到确定性层（CodeFuse-Query GDL，报告一 §3.6）
- **三层金字塔定位**：手写微基准（CASTLE 式）只做 smoke test/FP 校准，不进主指标（微基准分数不能外推到 PR 级）；主指标只看真实 commit 构造的 PR 级样本
- 回放结果即 §2.4「场景 prompt 改进提案」的客观依据：某 CWE recall 持续低 → 提炼 checklist 改进提案进 quarantine

### 2.5 记忆最短链路（`memoryd`，SQLite 单文件）

schema（架构文档 §4 的 MVP 子集，砍掉 consumers/ttl/trust 细分，保留治理必需字段）：

```sql
CREATE TABLE memories (
  id TEXT PRIMARY KEY,
  kind TEXT NOT NULL,              -- review_finding | convention | incident_pattern
  status TEXT NOT NULL DEFAULT 'quarantine',   -- quarantine | active | archived
  content TEXT NOT NULL,           -- 必须含 file:line 证据
  modules TEXT NOT NULL,           -- JSON array of glob
  bound_paths TEXT NOT NULL,       -- MVP 仅记录，失效引擎 V1 才消费
  evidence TEXT NOT NULL,          -- JSON: {change, commit_sha, review_artifact}
  created_at TEXT NOT NULL, reviewed_by TEXT, reviewed_at TEXT
);
```

三个命令即全部接口：

- `memory-propose.sh < finding.json`：schema 校验（无 file:line 证据 → 拒收）→ 插 quarantine。由 reviewer 工件自动触发：只提炼 `severity=critical/important 且 resolved=true` 的 finding
- `memory-approve.sh <id> [--reject <reason>]`：人工（MDE）审核；写 reviewed_by/at
- `memory-recall.sh <path...>`：`modules` glob 匹配 → 输出 active 条目（拼接进 `context.md`）。**纯 SQL LIKE/GLOB 匹配，无向量、无语义**（D7：MVP 宁可漏召）

## 3. 主流程（/sdd-review 命令体）

```
1. scripts/review-package.sh          → 生成输入包（diff + spec + 场景路由（§2.4）+ 记忆召回）
2. 派发 task-reviewer subagent         → fresh context，输入 = 输入包路径
3. reviewer 产出 findings              → controller 要求修复或 dispute
4. 修复后 re-review（最多 2 轮熔断）     → 全清写 CLEAN；仍有残留写 ESCALATED（逐条 ruling）→ 工件落 .git/review-gate/<session>.json
5. memory-propose.sh（自动）           → 高严重度已修复 finding 进 quarantine
6. 提示：「N 条记忆待审核」            → MDE 定期跑 memory-approve.sh
```

与 OpenSpec 的挂接：在 change 的 schema 中把 `review` 加为 `implement` 前的 artifact（报告一 §1.3 schema 机制）；`/sdd-review` 在 `/opsx:apply` 之后、archive 之前运行。

## 4. 度量埋点（MVP 即埋，否则试点无数据）

每次门禁拦截/放行、每次评审轮数、每条 finding 的 severity/resolved、每条记忆的 propose/approve/reject，全部 append 到 `.review/metrics.jsonl`。试点结束回看三个数：评审轮数均值（≤2）、quarantine 积压、漏网 bug 数。场景维度追加一项：per-scenario 命中/漏检统计（finding 记 `scenario` 字段），为场景库调优供数据。

## 5. 验收标准（与 README §4 MVP 一致）

- [ ] 改动 >20 行且无有效工件时，`git commit` 100% 被拦截
- [ ] 门禁脚本故障时放行（fail-open 测试：故意造语法错误验证）
- [ ] 评审工件 hash 绑定生效：评审后改动任意文件再 commit → 被拦截
- [ ] 部分 stage 时（存在 unstaged 改动）commit 被拒并提示先完整暂存
- [ ] 双会话并行评审互不覆盖工件（§2.1 会话隔离路径生效）
- [ ] ESCALATED 工件放行且每条残留 finding 带 ruling、metrics 可见
- [ ] quarantine 条目未经 approve 不出现在 `memory-recall.sh` 输出
- [ ] 无 file:line 证据的 propose 被拒收
- [ ] 场景路由生效：改 C++ 文件时注入 memory-leak/null-deref checklist，改 Markdown 时不注入任何场景
- [ ] 场景基线可回放：用历史缺陷案例集跑出 per-scenario precision/recall 基线并存档

## 6. 已知的 MVP 局限（如实记录）

- 无失效引擎：记忆可能过期，靠审核人把关；V1 才解决
- 记忆召回纯路径匹配：跨模块的"类似问题"召回不到——接受，MVP 验证的是治理闭环而非召回质量
- 单宿主（Claude Code）：hook 配置与 subagent 定义是 Claude Code 格式；脚本层（scripts/、memory/）天然宿主无关，V2 迁移成本低
