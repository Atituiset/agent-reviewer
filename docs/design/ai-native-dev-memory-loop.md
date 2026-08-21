# AI-Native 开发闭环设计：评审结论 → 审核入库 → 回喂 coding/review 的记忆飞轮

> 日期：2026-08-21
> 性质：设计概念文档（v0.1），基于两份前置调研：
> - `docs/research/sdd-code-reviewer-landscape.md`（报告一：SDD + Code Reviewer）
> - `docs/research/multi-agent-memory-communication-review.md`（报告二：多智能体记忆/通信）
> 以及 2026-08-21 的 prior-art 专项检索（见附录 B）

---

## 0. 一句话定义

当开发团队全部由 AI coding agent 构成时，把 **coding session 摘要与 code review 结论提炼为团队记忆资产**——初始为待审核态（quarantine），经审核后入正式库——并在后续 coding 与 review 中被确定性消费；记忆条目绑定代码版本，代码变更时自动降级回待审核态。形成自我增强的飞轮。

**Prior-art 结论（检索于 2026-08-21）**：该完整闭环**未发现现成实现**，但每个组件都有强相邻先例（见 §6），组合点即空白——在研究、产品和开源三个维度上都尚未被占据。

---

## 1. 愿景与边界

- **目标场景**：AI-native 研发团队——代码生成与代码检视都以 agent 为一等执行者，人（MDE / Tech Lead）退到审核与仲裁位
- **非目标**：不发明新的 agent 通信协议（用 A2A / subagent 派发）；不自建记忆引擎内核（用 mem0/Graphiti 或 SQLite-vec 类）；不做模型训练级反馈（那是厂商级飞轮，见 Steve Yegge 的提法，非本设计范围）
- **核心命题**：团队级记忆的**治理**（审核、失效、证据链）比记忆的存储与检索更关键——现有商业产品（CodeRabbit Learnings、Greptile 长期记忆）恰恰缺治理层，陈旧记忆污染已被多方实证

## 2. 总体架构：四层

```
┌─────────────────────────────────────────────────────┐
│ L4 消费层  coding agent（上下文注入）+ reviewer agent │
│           （评审输入四元组）                           │
├─────────────────────────────────────────────────────┤
│ L3 治理层  quarantine 状态机 + 审核 gate + 失效引擎    │  ← 本设计的核心增量
├─────────────────────────────────────────────────────┤
│ L2 记忆层  团队记忆库（条目化、带 provenance、分层）    │
├─────────────────────────────────────────────────────┤
│ L1 生产层  SDD 工作流（OpenSpec 式）+ reviewer 管线    │
│           （OCR 式确定性管线 + subagent 派发）          │
└─────────────────────────────────────────────────────┘
```

- **L1 生产层**：直接复用报告一 §6.1 的骨架——OpenSpec 式 SDD（changes/ + delta specs + schema 依赖图）+ OCR 式确定性评审管线 + superpowers 式 reviewer subagent 派发
- **L2 记忆层**：条目化存储（schema 见 §3），底座选型 mem0（自托管、三级作用域）或 mcp-memory-service（SQLite-vec 轻量路线）
- **L3 治理层**：quarantine → 审核 → 入库 → 失效/降级 的状态机（§4），是本设计相对所有现有产品的差异点
- **L4 消费层**：coding 侧走 OpenSpec 的 `context:` 主动注入模式；review 侧作为评审输入第四元（diff + spec + 规则 + **历史记忆**）

## 3. 记忆条目 Schema（设计要点）

```yaml
id: mem_<ulid>
kind: review_finding | session_lesson | incident_pattern | convention | api_usage
status: quarantine | active | degraded | archived      # 状态机见 §4
content: <自然语言条目，必填，含 file:line 级证据引用>
evidence:                                               # provenance 一等字段
  source_session: <session id>
  source_change: openspec/changes/<name>                # 或 PR 号
  commit_sha: <产生该结论时的 commit>
  review_ref: <评审工件路径 / verdict>
scope:
  modules: ["payment/**", "auth/**"]                    # 确定性召回锚点
  consumers: [coding | review]                          # 消费者视图标签
severity: low | medium | high                           # 决定审核路由（§4.2）
trust:
  confirmations: 0        # 后续被独立验证的次数
  violations: 0           # 后续被发现失效/误导的次数
lifecycle:
  created_at / reviewed_at / reviewer: <MDE id 或 "auto">
  bound_paths: ["src/payment/lock.go"]                  # 失效引擎的监听对象
  ttl_hint: stable | working                            # 借鉴 synapto 分层衰减
```

设计依据：

- **provenance 一等字段**：没有证据链的记忆入库 = 把 review theater 固化成团队资产（报告一 §5 的变种）。可回溯到 session、diff、评审结论三者
- **consumers 视图分离**：coding agent 要"怎么做"（模式、约定），reviewer 要"哪里错过"（事故史、边界案例）；入库时打标，召回时按角色过滤，避免互相淹没
- **bound_paths**：失效引擎的监听对象，是「代码变更 → 记忆降级」的机械挂钩

## 4. 治理层状态机（核心设计）

```
                 ┌──────────────────────────────┐
                 │                              │
   产生 ──→ QUARANTINE ──审核通过──→ ACTIVE ──被新证据确认──→ ACTIVE (confirmations+1)
           （待审核态）   │              │
                     审核驳回         │ 绑定的 bound_paths 发生代码变更
                       │              ▼
                       ▼         DEGRADED（降回待审核）
                    ARCHIVED         │
                                 重新审核 → ACTIVE / ARCHIVED

   任何状态：trust.violations 超阈值 → ARCHIVED（信任反馈自清洁，借鉴 synapto）
```

### 4.1 写入来源（自动提炼）

- **review 结论**：reviewer subagent 的评审工件中， verdict 为 Must-Fix 且修复确认的 finding → 自动提炼为 `incident_pattern` 条目进 quarantine（"这类改动曾在 X 处引入死锁"）
- **session 综合**：coding session 结束时的 wrap-up 摘要 → `session_lesson` 进 quarantine（参照 lamarck / claude-mem 的压缩模式，但加治理门）
- **人工撰写**：MDE 直接写 `convention` 条目，可直入 active（人已审过）

### 4.2 审核路由（解决 MDE 吞吐瓶颈）

agent 速度产生条目，人工逐条审跟不上——抄 OCR 的 severity/category 路由：

| severity | 判定 | 路由 |
|---|---|---|
| low | 事实性、可机械验证（构建命令、目录约定） | **自动入库**（agent 一审即可） |
| medium | 模式类（推荐写法、API 用法） | agent 一审 + MDE 批量二审（每日队列） |
| high | 安全性/正确性断言（"该并发模型是安全的"） | **必须 MDE 人工审核**，附 evidence 链 |

校准指标沿用报告一 §4.3：入库后发现误导性条目的频率（门太松）；审核队列积压时长（门太紧）。

### 4.3 失效引擎（本设计最独特的机制）

**问题**：TTL 衰减只解决低相关性条目；危险的是**高相关性但已失效**的记忆（tianpan.co 的论断，CodeRabbit Learnings 的陈旧条目问题已实证）。

**机制**：

1. 条目 `bound_paths` 对应的文件在 git 中发生变更 → 条目自动 ACTIVE → DEGRADED，通知原审核人
2. OpenSpec 的 **archive 事件是天然的失效触发点**：delta spec 合并进主 specs 时，凡 scope.modules 与被修改 requirement 重叠的条目批量降级
3. 仓库级粗粒度兜底：会话开始时检测 commit 漂移（Codified Context 模式），提示"自上次会话以来 N 条记忆可能过时"
4. 条目级 fine-grain 召回校验：召回时对 `evidence.commit_sha` 与当前 HEAD 做 diff 检查，命中 bound_paths 则降权并标注"待复核"

### 4.4 消费侧：确定性召回，不是语义瞎搜

守住报告一 §3.5 OCR 的教训——**记忆检索注入应工程化**：

- **按模块标签精确召回**：变更文件的路径 → `scope.modules` 匹配 → 直接注入对应条目（reviewer 的 prompt 里给结论，不是给记忆库的搜索权）
- **评审输入四元组**：reviewer prompt = diff 文件 + spec/plan 条目 + 规则文件 + **按模块召回的 active 记忆**
- **coding 侧**：走 OpenSpec `openspec instructions` 式的主动注入——生成 tasks 时把相关 convention/api_usage 条目编入 instructions
- 语义检索只作为补充通道（跨模块的"类似问题"发现），不作为主路径

## 5. Agent 通信与组织形态

沿用报告二 §4.2 的分层结论，不混用两种范式：

- **流水线内**（implementer → reviewer → fixer）：subagent 派发 + 工件即接口，绝不给会话历史（superpowers 纪律）
- **跨工具/跨团队**（Claude Code 产出交 Codex 复审、SRE agent @ 开发 agent、异步长任务）：A2A 协议（v1.0 已稳定，Linux Foundation 治理）；Agent Card 做服务发现，task/message 模型承载 @提及语义
- **记忆库本身作为 MCP server** 暴露给所有 agent 宿主（remember/recall 工具面），写入只接受 quarantine 态

## 6. Prior-art 对照表（每个组件的最近邻实现与缺口）

| 组件 | 最近邻实现 | 缺口（= 本设计的增量） |
|---|---|---|
| 评审结论 → 记忆 → 回喂 review | CodeRabbit Learnings、Greptile 长期记忆（商业可用） | 无审核门、自动入库、无版本绑定；陈旧条目污染已被实证 |
| 会话摘要 → 团队记忆 | lamarck（18★）、Learnings.md 社区模式、Amp thread 分享、claude-mem（91.4k★） | 个人向/原始分享，未提炼为受治理资产 |
| Quarantine + 审核晋级 | **LOGOS 论文**（arXiv:2607.10878，"proposal is not promotion"，三层信任 + promotion gate）、LangChain Agent Builder（逐条人工审批写入）、MemGuard/MeshGuard（安全向 quarantine） | 均不针对团队开发知识，无代码语境 |
| 记忆 ↔ 代码版本绑定 | projectmem（746★，file:line 绑定 + precheck_file 告警）、Codified Context（arXiv:2602.20478，commit 漂移检测） | 用于告警/提示，**非条目级自动失效/降级** |
| 失效/腐化问题 | arXiv:2606.24775（invalidation 命名核心失败模式）、tianpan.co（TTL 不够） | 停在问题陈述，机制方案稀缺 |
| 经验学习学术原型 | Voyager（技能入库前自我验证）、ExpeL（经验提炼回喂）、ACE（playbook 增量演化）、SWE-Exp（issue 经验复用） | 自评自改，无人类 gate，无代码绑定 |
| Agent 舰队共享底座 | Beads（26.5k★，Steve Yegge，git-backed 任务/记忆图） | 定位是任务状态，非评审结论资产 |

**结论**：LOGOS 的「proposal ≠ promotion」治理门 + CodeRabbit 式评审反馈自动提炼 + projectmem/Codified Context 的代码版本绑定 + **条目级自动失效/降级**（目前无人做实）= 本设计的组合创新点。

## 7. 风险与对策

| 风险 | 依据 | 对策 |
|---|---|---|
| 陈旧记忆污染（飞轮变负反馈） | CodeRabbit Learnings 评测、Learnings.md 警告、arXiv:2606.24775 基准 | §4.3 失效引擎 + trust.violations 自清洁；宁可召回不足不可召回错误（precision 优先，同 OCR 哲学） |
| Review theater 固化 | 报告一 §5 | 条目必须有 file:line 证据 + 来源评审工件；无证据不入 quarantine |
| MDE 审核积压 | 全员 agent 速度的必然结果 | §4.2 severity 路由；agent 一审 + 人二审；批量队列 |
| 误报型失效（合法变更触发降级） | projectmem 作者自承的 false positive 问题 | 降级不等于删除；degraded 条目召回时标注而非隐藏；confirmations 高的条目降级需人工确认 |
| 记忆库成为注入面 | LangChain 逐条审批的动机（防注入） | 写入只接受 quarantine；外部来源条目默认 high severity 路由 |
| 验证成本反噬 | METR 实验（AI 反而慢 19%）、报告一 §5 | 小改动豁免；整条链路按改动规模自适应强度 |

## 8. 落地路径建议

1. **MVP（2-3 周，5-10 人试点）**：只做 review 结论 → quarantine → 人工审核 → 按模块注入 reviewer 这一条最短链路；记忆底座用 SQLite-vec 单文件方案；不接 A2A
2. **V1**：加失效引擎（git hook 监听 bound_paths）+ session 综合写入 + coding 侧注入（OpenSpec instructions 挂点）
3. **V2**：severity 自动路由 + trust 反馈 + 跨工具 A2A 适配；评估换 mem0/Graphiti 底座
4. **全程度量**：评审漏网率、平均每 PR 评审轮数（报告一 §4.3）、记忆召回命中率、degraded 条目占比、审核队列时长

---

## 附录 A：与前置调研的对应关系

- L1 生产层 ← 报告一 §6.1 通用骨架、§3.5 OCR、§4.2 superpowers
- L4 评审输入四元组 ← 报告一 §6.3 机会点 #1 扩展 + 报告二 §4.1
- 确定性召回 ← 报告一 §3.5（OCR 教训）、报告二 §4.1
- 两层通信范式 ← 报告二 §4.2
- 写入门禁 ← 报告二 §4.3 + 报告一 §4.3（证据原则）

## 附录 B：Prior-art 信源（2026-08-21 检索，star 数为 API 实测）

**商业产品的 learnings/记忆**： [CodeRabbit Learnings 文档](https://docs.coderabbit.ai/knowledge-base/learnings) · [Greptile 长期记忆更新](https://www.greptile.com/blog/greptile-update) · [Greptile Custom Context](https://www.greptile.com/docs/mcp/custom-context) · [Copilot knowledge bases 退役公告](https://github.blog/changelog/2025-08-20-sunset-notice-copilot-knowledge-bases/) · [Cursor Team Rules](https://docs.cursor.com/context/rules-for-ai) · [Amp manual](https://ampcode.com/manual) · [CodeRabbit: AI Second Brain](https://www.coderabbit.ai/guides/ai-second-brain-for-engineering) · [MartinZoeller 的 CodeRabbit 评测（陈旧 learnings 问题）](https://www.martinzoeller.com/en/blog/coderabbit-ai-review-is-it-worth-it)

**学术**： [LOGOS arXiv:2607.10878](https://arxiv.org/html/2607.10878v1)（quarantine/promotion gate 最接近） · [ExpeL arXiv:2308.10144](https://arxiv.org/abs/2308.10144) · [ACE arXiv:2510.04618](https://arxiv.org/abs/2510.04618) · [Voyager arXiv:2305.16291](https://arxiv.org/abs/2305.16291) · [SWE-Exp arXiv:2507.23361](https://arxiv.org/html/2507.23361v2) · [agent-native memory arXiv:2606.24775](https://arxiv.org/html/2606.24775v1)（invalidation 失败模式） · [Codified Context arXiv:2602.20478](https://arxiv.org/abs/2602.20478)（commit 漂移检测）

**开源**： [riponcm/projectmem](https://github.com/riponcm/projectmem)（746★，file:line 绑定 + precheck 告警 + Memory-as-Governance） · [gastownhall/beads](https://github.com/gastownhall/beads)（26.5k★，Steve Yegge） · [johnlindquist/lamarck](https://github.com/johnlindquist/lamarck) · [NicolasPrimeau/artel](https://github.com/NicolasPrimeau/artel)（记忆与 repo 一致性 compile mode） · [ac12644/MemGuard](https://github.com/ac12644/MemGuard)（quarantine + 陈旧校验） · [Learnings.md 模式教程](https://www.mindstudio.ai/blog/self-learning-ai-skill-system-learnings-md-wrap-up) · [awesome-harness-engineering](https://github.com/ai-boost/awesome-harness-engineering)（3,675★）

**组织形态讨论**： [Steve Yegge: Gas Town / 8 levels](https://www.augmentcode.com/guides/steve-yegge-8-levels-ai-assisted-development) · [Pragmatic Engineer 访谈](https://newsletter.pragmaticengineer.com/p/steve-yegge-on-ai-agents-and-the) · [tianpan.co: Agent Memory Is a Cache With No Invalidation Policy](https://tianpan.co/blog/2026-05-16-agent-memory-cache-without-invalidation-policy)

**存疑说明**：claude-mem（91.4k★）与 beads（26.5k★）的 star 数为 API 实测但增长曲线异常，正式引用前建议复核；LOGOS、Codified Context 等 2026 年新论文未经同行评审确认，引用时注意。
