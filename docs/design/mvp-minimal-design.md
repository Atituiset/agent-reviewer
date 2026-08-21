# MVP 最小设计：评审最短闭环 + 记忆最短链路

> 版本：v0.1 · 2026-08-22
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
├── scripts/
│   ├── review-package.sh        # 打包 diff + spec 上下文 → 评审输入
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

### 2.1 评审工件（`.review/last-review.json`）

评审通过的唯一凭证，hook 只认它：

```json
{
  "diff_hash": "sha256 of `git diff HEAD` 的规范输出",
  "verdict": "CLEAN | ISSUES_FOUND",
  "reviewed_at": "ISO8601",
  "reviewer": "task-reviewer",
  "findings": [
    {"file": "src/x.go", "line": 42, "severity": "critical|important|minor",
     "category": "bug|security|...", "summary": "…", "resolved": true}
  ],
  "spec_ref": "openspec/changes/<name>/"
}
```

校验规则（`verify-artifact.sh`，纯 shell + sha256sum + jq）：

1. `diff_hash` == 当前 `git diff HEAD | sha256sum`——**评审后代码再动过一个字节即失效**（报告一 §4.3）
2. `verdict == CLEAN`，或所有 findings 均 `resolved: true`
3. 工件生成时间 < 24h

### 2.2 门禁 hook（`hooks/pre-commit-gate.sh`）

挂在 `PreToolUse`（matcher: `Bash`），只拦截含 `git commit` 的命令：

```
放行条件（任一满足即放行）：
  - diff 总行数 < 20
  - diff 只触及 **.md / docs/**（纯文档豁免）
  - kill switch 文件 .review/DISABLED 存在
拦截时：
  - verify-artifact.sh 通过 → 放行
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
                                #   - 规则文件（项目评审 checklist）
                                #   - memory-recall.sh 按变更文件路径召回的 active 记忆
  ```
- 评审双通道（D3）：conformance（逐条对照 spec/plan）+ correctness（红队视角挑 diff 本身的错）
- 输出纪律（D4）：每条 finding 必须有 `file:line` + 可复现理由；"could be cleaner" 类不收；结论按 0–100 置信度，只报 ≥80
- reviewer 只读：无 Edit/Write 权限（工具白名单）

### 2.4 记忆最短链路（`memoryd`，SQLite 单文件）

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
1. scripts/review-package.sh          → 生成输入包（diff + spec + 规则 + 记忆召回）
2. 派发 task-reviewer subagent         → fresh context，输入 = 输入包路径
3. reviewer 产出 findings              → controller 要求修复或 dispute
4. 修复后 re-review（最多 2 轮熔断）     → 全清 → 写 .review/last-review.json
5. memory-propose.sh（自动）           → 高严重度已修复 finding 进 quarantine
6. 提示：「N 条记忆待审核」            → MDE 定期跑 memory-approve.sh
```

与 OpenSpec 的挂接：在 change 的 schema 中把 `review` 加为 `implement` 前的 artifact（报告一 §1.3 schema 机制）；`/sdd-review` 在 `/opsx:apply` 之后、archive 之前运行。

## 4. 度量埋点（MVP 即埋，否则试点无数据）

每次门禁拦截/放行、每次评审轮数、每条 finding 的 severity/resolved、每条记忆的 propose/approve/reject，全部 append 到 `.review/metrics.jsonl`。试点结束回看三个数：评审轮数均值（≤2）、quarantine 积压、漏网 bug 数。

## 5. 验收标准（与 README §4 MVP 一致）

- [ ] 改动 >20 行且无有效工件时，`git commit` 100% 被拦截
- [ ] 门禁脚本故障时放行（fail-open 测试：故意造语法错误验证）
- [ ] 评审工件 hash 绑定生效：评审后改动任意文件再 commit → 被拦截
- [ ] quarantine 条目未经 approve 不出现在 `memory-recall.sh` 输出
- [ ] 无 file:line 证据的 propose 被拒收

## 6. 已知的 MVP 局限（如实记录）

- 无失效引擎：记忆可能过期，靠审核人把关；V1 才解决
- 记忆召回纯路径匹配：跨模块的"类似问题"召回不到——接受，MVP 验证的是治理闭环而非召回质量
- 单宿主（Claude Code）：hook 配置与 subagent 定义是 Claude Code 格式；脚本层（scripts/、memory/）天然宿主无关，V2 迁移成本低
