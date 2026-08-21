# ai-native-dev-memory（ANDM）系统设计

> 版本：v0.1 · 2026-08-21
> 性质：系统设计文档——将《AI-Native 开发闭环设计》（`docs/design/ai-native-dev-memory-loop.md`，下称「概念文档」）落成可实施的系统架构
> 前置：`docs/research/sdd-code-reviewer-landscape.md`（报告一）、`docs/research/multi-agent-memory-communication-review.md`（报告二）

---

## 1. 定位

**ANDM 是 AI-native 研发团队的「受治理团队记忆层」**：沉淀 coding session 与 code review 的结论为记忆资产，经 quarantine 审核后入库，确定性回喂给后续 coding 与 review，并随代码变更自动失效。

一句话差异化：**现有产品做「记忆的存储与检索」，ANDM 做「记忆的治理」**——审核状态机、证据链、代码版本绑定失效，是目前商业产品（CodeRabbit Learnings / Greptile）和开源项目（mem0 / synapto / projectmem）都缺失的层（检索结论见概念文档附录 B）。

## 2. 设计原则（从调研提炼，逐条有出处）

| # | 原则 | 出处 |
|---|---|---|
| P1 | 治理 > 存储：写入必须过状态机，任何条目初始为 quarantine | LOGOS（arXiv:2607.10878）"proposal is not promotion" |
| P2 | 证据链是一等公民：无 file:line 证据的条目不产生 | 报告一 §4.3（imti.co 反 review theater 校准） |
| P3 | 召回走确定性路径（模块标签匹配），语义检索只作补充 | 报告一 §3.5（OCR「确定性工程 × Agent」） |
| P4 | 宁可召回不足，不可召回错误（precision 优先） | OCR benchmark 策略；CodeRabbit 陈旧 learnings 教训 |
| P5 | 条目绑定代码版本，代码变更即降级（不是 TTL 衰减） | tianpan.co「无失效策略的缓存」；arXiv:2606.24775 |
| P6 | 门禁 fail-open + 低风险豁免 | 报告一 §4.3 / §5 |
| P7 | 进程内派发用 subagent + 工件，跨边界才用 A2A | 报告二 §4.2 |

## 3. 系统架构

```
        ┌───────────────────── 生产者 ─────────────────────┐
        │  reviewer 管线          coding session            │
        │  (评审工件 verdict)     (wrap-up 摘要)             │
        └──────────┬───────────────────────┬───────────────┘
                   ▼                       ▼
            ┌──────────────────────────────────┐
            │  Distiller（提炼器）               │  评审工件/会话日志 → 条目草稿
            │  LLM 提炼 + 模板化 schema 校验      │  （无证据字段直接拒收 → P2）
            └──────────────┬───────────────────┘
                           ▼ (status=quarantine)
            ┌──────────────────────────────────┐
            │  Governance Engine（治理引擎）★    │  状态机 + severity 路由
            │  quarantine→active→degraded→archived│ + 审核队列 + trust 计分
            └──────────────┬───────────────────┘
                           ▼
            ┌──────────────────────────────────┐
            │  Memory Store（记忆库）            │  MVP: SQLite + sqlite-vec
            │  条目 + 索引（模块倒排 + 向量）      │  V2: mem0/Graphiti 自托管
            └──────────┬───────────────────┘
                       ▼
        ┌──────────────────────────────────────┐
        │  Recall & Injection（召回注入层）       │
        │  ① MCP server（remember/recall/...）   │
        │  ② reviewer prompt 组装器              │
        │  ③ OpenSpec instructions 挂点          │
        └──────────────────────────────────────┘
                       ▲
        ┌──────────────┴───────────────────────┐
        │  Invalidation Engine（失效引擎）★      │
        │  git hook 监听 bound_paths 变更        │
        │  + OpenSpec archive 事件 + commit 漂移  │
        └──────────────────────────────────────┘

★ = 相对现有产品的核心增量模块
```

## 4. 数据模型（MVP 直接可用的 SQLite schema）

```sql
CREATE TABLE memories (
  id            TEXT PRIMARY KEY,            -- mem_<ulid>
  kind          TEXT NOT NULL,               -- review_finding|session_lesson|incident_pattern|convention|api_usage
  status        TEXT NOT NULL DEFAULT 'quarantine',  -- quarantine|active|degraded|archived
  content       TEXT NOT NULL,               -- 自然语言条目，必须含证据引用
  severity      TEXT NOT NULL,               -- low|medium|high → 审核路由
  consumers     TEXT NOT NULL,               -- JSON array: ["coding","review"]
  modules       TEXT NOT NULL,               -- JSON array of glob: ["payment/**"]
  bound_paths   TEXT NOT NULL,               -- JSON array: 失效引擎监听对象
  evidence      TEXT NOT NULL,               -- JSON: {session_id, change, commit_sha, review_ref}
  confirmations INTEGER NOT NULL DEFAULT 0,
  violations    INTEGER NOT NULL DEFAULT 0,
  created_by    TEXT NOT NULL,               -- agent id / human id
  reviewed_by   TEXT,                        -- MDE id（auto 表示自动路由通过）
  created_at    TEXT NOT NULL,
  reviewed_at   TEXT,
  embedding     BLOB                         -- sqlite-vec 向量（补充召回通道）
);

CREATE INDEX idx_mem_modules ON memories(modules);   -- 实际用 FTS5 或倒排表
CREATE TABLE audit_log (                             -- 所有状态迁移可追溯
  id INTEGER PRIMARY KEY, mem_id TEXT, from_status TEXT, to_status TEXT,
  actor TEXT, reason TEXT, at TEXT
);
```

关键约束在应用层强制：`evidence` 不含 `commit_sha` + 至少一个 `file:line` 引用 → Distiller 拒收（P2）。

## 5. 接口面

### 5.1 MCP server（对所有 agent 宿主暴露）

| 工具 | 行为 | 权限 |
|---|---|---|
| `recall(query, module, consumer)` | 确定性模块匹配为主，向量为辅；只返回 `active`（`degraded` 标注"待复核"降权返回） | 所有 agent 可读 |
| `propose(content, kind, evidence, ...)` | 写入 quarantine；schema 校验失败即拒 | 所有 agent 可写，但只进 quarantine（防注入面，P1） |
| `confirm(mem_id)` / `violate(mem_id, reason)` | trust 计分；violations 超阈值自动 archived | reviewer agent / 人 |
| `approve(mem_id)` / `reject(mem_id, reason)` | 审核操作，写 audit_log | 仅 MDE 角色（或 low severity 的 auto 路由） |
| `review_queue(severity?)` | 待审核队列（MDE 每日批量处理） | MDE |

### 5.2 两个注入挂点（消费侧的工程化，P3）

- **reviewer prompt 组装器**：reviewer subagent 派发时（superpowers 式），controller 用 diff 涉及的文件路径 → glob 匹配 `modules` → 把命中条目**直接编进 prompt**（四元组：diff + spec + 规则 + 记忆）。agent 无搜索记忆库的自由
- **coding 侧**：复用 OpenSpec `openspec instructions <artifact> --json` 的主动注入模式——生成 tasks/proposal 时把 `consumers=["coding"]` 的 convention/api_usage 条目编入 instructions

### 5.3 失效引擎的触发器

1. **git post-commit/post-merge hook**：diff 变更文件 ∩ 条目 `bound_paths` ≠ ∅ → active → degraded，通知原 reviewed_by
2. **OpenSpec archive 事件**：delta spec 合并时，scope 与被改 requirement 重叠的条目批量降级（spec 层面失效）
3. **会话开始时的 commit 漂移检查**（Codified Context 模式）：粗粒度提示「自条目 E 创建以来其绑定模块有 N 次提交」

## 6. 核心流程

### 6.1 review 结论入库（最短链路 = MVP）

```
reviewer subagent 产出评审工件（verdict + findings, file:line 齐全）
  → Distiller 提炼 Must-Fix 且已修复确认的 finding 为 incident_pattern 草稿
  → schema 校验（证据不全 → 拒收，报告一 P2）
  → severity 判定：high → MDE 队列 / medium → agent 一审+MDE 批量二审 / low → auto approve
  → active，按 modules 建立倒排索引
  → 下次同模块 review：prompt 组装器自动携带该条目
```

### 6.2 失效与复活

```
git hook 检测到 bound_paths 变更 → 条目 degraded → 通知审核人
  → 审核人确认「仍然成立」→ active（confirmations+1）
  → 审核人确认「已过时」→ archived（audit_log 留痕）
```

## 7. 与 SDD 工作流的挂接（OpenSpec 式）

- 在 OpenSpec schema 依赖图中插入 review artifact：`proposal → (specs ∥ design) → tasks → **review** → implement`（报告一 §6.1）
- review 命令执行时：① 派 reviewer subagent ② 调用 prompt 组装器注入记忆 ③ 评审完成时触发 Distiller
- archive 时：sync delta specs + **触发失效引擎的 spec 级降级**——一个事件同时更新 spec 与记忆两层 source of truth

## 8. 技术选型

| 组件 | MVP | 规模化后 |
|---|---|---|
| 记忆底座 | SQLite + sqlite-vec（参照 mcp-memory-service） | mem0 自托管 / Graphiti（知识图谱） |
| 协议面 | MCP server | + A2A（跨团队/跨工具时，报告二 §4.2） |
| 提炼/审核模型 | 复用团队现有 LLM 端点；severity 路由用便宜模型，入库裁决用强模型（模型分层，报告一 §4.9-7） | — |
| 失效监听 | git hooks + OpenSpec CLI 事件 | + 类 CodeFuse-Query 变更影响分析（精确到函数级，报告一 §3.6） |
| 宿主集成 | Claude Code skill/plugin（形态 A 先行，报告一 §6.2 形态 C 建议） | 多宿主 CLI（形态 B） |

## 9. 里程碑与度量

- **MVP（2-3 周，5-10 人）**：§6.1 最短链路。SQLite 底座 + MCP server + reviewer prompt 注入 + 人工审核队列
- **V1**：失效引擎（git hook + archive 事件）+ coding 侧注入 + session 综合写入
- **V2**：trust 自清洁 + severity 自动路由 + A2A 适配 + 底座迁移评估
- **度量**（全程）：评审漏网率、每 PR 评审轮数（报告一 §4.3）、记忆召回命中率、degraded 占比、审核队列积压时长、**误导性条目发现率**（飞轮是否反转的核心指标）

## 10. 开放问题

1. degraded 条目的召回策略：标注降权 vs 隐藏——需要试点数据决定（projectmem 的 false positive 教训）
2. 条目的粒度：一条记忆应该多小？太大难失效（bound_paths 过宽误降级），太小提炼成本高
3. 多仓/多团队场景下 modules 命名空间的治理
4. 审核人本身的激励问题——MDE 队列如果无人处理，quarantine 会变成垃圾场（需要试点验证 4.2 的路由比例）

---

## 附录：设计依据索引

- 状态机与 quarantine：概念文档 §4；LOGOS 论文；MemGuard/MeshGuard
- Schema 与 provenance：概念文档 §3；报告一 §4.3（imti.co）
- 失效引擎：概念文档 §4.3；tianpan.co；Codified Context；projectmem
- 确定性召回：报告一 §3.5（OCR）；报告二 §4.1
- SDD 挂接：报告一 §1.3（OpenSpec schema 机制）、§6.1
- 通信分层：报告二 §4.2
- 选型：报告二 §2（mem0/mcp-memory-service 对比）；报告一 §3.6（CodeFuse-Query）
