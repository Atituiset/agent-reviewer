# ai-native-dev-memory（ANDM）系统设计

> 版本：v0.2 · 2026-08-21（v0.2 新增 §10：记忆工程机制设计）
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

## 10. 记忆工程机制深化（v0.2，来自 记忆系统工程）

机制参考：`一份记忆系统工程笔记`（覆盖 60+ 公开论文与生产实践）。单用户个人记忆与团队研发记忆场景不同（差异见 §10.6），但记忆系统工程机制大量可迁移。

### 10.1 总体原则

- **统一存储 + 类型标记**：「逻辑分离、物理可合并」——一张表 + `kind` 字段 + 不同索引策略，与 §4 schema 一致，不分库
- **读写双管线分离**：Write = `PREPROCESS → IMPORTANCE → DEDUP → STORE` + 异步 consolidation；Read = `QUERY EXPANSION → HYBRID SEARCH → RANKING → CONTEXT ASSEMBLY`。**quarantine 就是插在写管线 STORE 之前的缓冲带**——治理门有现成的管线理论支撑
- **Build vs Buy**：「记忆系统的门槛不在基础设施，而在记忆编排层」——ANDM 的差异化全在治理规则，向量库/存储全用现成组件（§8 选型不变）
- **MCP server 形态**：`remember/recall/forget/search` tools + `memory://module/<path>` resources（后者正好服务确定性召回）+ 高危动作 `requiresConfirmation: true`

### 10.2 条目模型增强（修订 §4 schema）

新增/明确三个字段，均有出处：

- `applies_to`：**可编程判定的适用守卫**（glob 匹配代码路径），不写含糊自然语言——工程实践 §1.2 的 `preconditions` 教训："preconditions 应写成可编程检查"
- `hit/miss` 埋点计数：召回后被采纳 vs 被忽略 vs 被标记误导——这是「误导性条目率」度量的数据源头（§4 的 `confirmations/violations` 细化为召回级埋点）
- `last_accessed_at`：**时效衰减锚定「上次被访问时间」而非创建时间**（检索命中即重置，模拟复述效应，Generative Agents 机制）——修正概念文档 §4.3 单纯 TTL 的思路

### 10.3 写入管线增强（修订 §6.1 Distiller）

- **前置过滤决策树**：个人意义? → 重复? → 含新事实? → 值得记忆?；研发语境的忽略清单：临时状态（"这个 PR 还没合"）、相似度 >0.9 的重复、**被纠正后的错误信息**（agent 一度误判、后被 review 纠正的结论绝不能成为团队记忆）
- **重要性评分公式（研发信号版）**，替代 通用版本的情感/交互信号：
  `Importance = w1×ReviewSeverity + w2×DecisionFinality + w3×ModuleCriticality + w4×InfoDensity + w5×FutureReferenceLikelihood`
  重要性分决定 quarantine 审核优先级与入库初始权重
- **写入前去重进 quarantine 之前**：LSH 近似 + cosine>0.95 合并——避免审核人重复审近似条目
- **冲突解决**（相似度 >0.85 且语义矛盾时）：裁决依据用「绑定代码版本新旧 + 审核人权限」替代纯 confidence；无法裁决则**双版本并存 + 冲突标注**，注入时同时呈现让 agent 向人确认——不强行二选一
- **混合压缩策略**：关键信息（决策、结论、TODO）用提取式保真；上下文叙述用生成式压缩（20:1）；token 级压缩（LLMLingua 类）精度风险高，**不适合承载 review 结论**
- **原文锚点**：摘要不可逆——每条提炼条目必须保留指向原始 session（Level 0）的链接，审核人可回溯原文判断提炼是否有损（强化 §4 的 evidence 字段）

### 10.4 生命周期深化（修订概念文档 §4.3 失效引擎）

- **聚合轴改为代码模块，不是日历时间**：通用的 Level 0→4 层级摘要按日/周/月聚合，ANDM 对应物是「同模块的 session 摘要与 review 结论跨会话归并为模块级经验条目」
- **记忆蒸馏触发条件**：「同一模块的同类 review 意见出现 ≥N 次且时间跨度 ≥7 天」→ 蒸馏为一条模块级规约条目（而不是存 N 条相似条目）。数量 + 时间双阈值防止单次集中事件误判为规律
- **时间衰减降级为兜底**：Ebbinghaus 分档 λ（episodic 0.01 / semantic 0.001 / procedural 0.0001）只用于「长期无人召回的条目自然沉底」；**主失效信号仍是代码变更**（§5.3 失效引擎不变）
- **pinned 保护（治理权边界）**：团队 lead 显式确认的条目（如架构决策）对自动失效免疫——失效引擎最高权限是「降级/移出召回池」，pinned 条目只能「标记待人工复核」；**物理删除只能由人执行**，默认软删除可恢复。对应三级保护优先级：人工 review 通过 > 人工确认的 agent 提炼 > 纯 agent 自动提炼

### 10.5 安全节（新增，quarantine 的理论加固）

工程实践 §17 的结论在团队研发记忆场景**更危险**：记忆会被自动注入大量后续会话，投毒一次的爆炸半径是团队级、持久化的。四件套必须做：

1. **「数据即指令」前提**：session 摘要来自 agent 输出，可能夹带被处理代码/issue 中的注入指令；未审核直接入库 = 把攻击面永久化——quarantine 的存在依据
2. **指令-数据隔离**（零成本必须做）：注入 prompt 时条目以明确的「数据」角色渲染，条目文本中的祈使句不得被当作指令
3. **注入检测预筛**：轻量分类器预筛 prompt-injection 特征，可疑条目保持隔离不进召回池；quarantine = 检测器预筛 + 人工终审两级
4. **蜜罐回归测试**：故意植入已知恶意样本，定期验证 quarantine 审核流与检测器的拦截有效性

### 10.6 明确不照搬的部分

- **隐私合规框架**（端侧优先、被遗忘权、端云加密）不适用——ANDM 需要的是 RBAC/审计/仓库级隔离
- **端侧实时性约束**（P95 <50ms、INT8 量化）不适用——注入发生在会话开始，秒级可接受
- **多设备 CRDT/LWW 同步**不需要——中心化服务 + git 式版本化即可
- **公开基准**（LongMemEval/LOCOMO）参考价值低——ANDM 基准只能自建（真实 PR/review 历史回放）

### 10.7 评估体系修订（补强 §9 度量）

| 指标 | 定义 | 目标 |
|---|---|---|
| **北极星：A/B 价值证明** | 有/无记忆注入下 coding 一次通过率、review 逃逸缺陷率对比 | 有记忆组显著更优，否则系统没有存在理由 |
| 失效引擎漏检率 | 绑定代码已变更但未降级的条目占比 | <3% |
| 真·误导率 | 注入后导致错误生成/误判的条目占比 | <1%，一票否决级 |
| 审核吞吐 | quarantine 条目在 SLA 内被审核的比例与积压量 | 积压趋零（否则 quarantine 变垃圾场，§11 开放问题 4） |
| 审核误杀率 | 正常条目被驳回比例 | <1%（过高则团队绕过治理） |
| 投毒拦截率 | 蜜罐样本被 quarantine 拦截比例 | >99% |

上线节奏照搬三级：**synthetic → human-curated → production shadow**（失效引擎与召回先只观察不生效，与人工选择对比达标后再切真实注入）；提炼模型换版本必须回归，防止 quarantine 质量基线漂移。

## 11. 开放问题

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
- 记忆工程机制（§10）：本地研究库 `memory-research`（记忆系统工程），章节 `src/01/03/04/05/14/16/17/19`；辅助 arXiv:2505.00675（记忆六原子操作）——ANDM 在六操作之外新增第七操作「审核（governance）」与「版本绑定失效」
