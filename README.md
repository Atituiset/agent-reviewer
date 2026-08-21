# agent-reviewer

> AI Coding 时代的 AI 检视：当代码由 agent 生成，评审也必须 agent 化——并且治理化。

## 1. 初衷与问题

AI Coding 工具（Claude Code、Codex、OpenCode 等）已经把代码生成提速了一个数量级，但代码检视（code review）环节没有跟上。由此产生三个结构性问题：

1. **评审时机太晚**：主流 AI 评审工具（PR-Agent、CodeRabbit 等）在 PR 打开后才介入，此时 commit/push 的成本已沉没，修复要再走一遍完整循环
2. **约束是建议性的**：写在 `CLAUDE.md`/`AGENTS.md` 里的评审规则遵守率约 80%，模型在认知负载下会"读了、自称考虑了、实际没走流程"——必须发生的评审需要机械门禁，而不是提示词自觉
3. **评审结论不沉淀**：每次评审发现的缺陷模式、事故教训随会话结束而消散，团队反复在同类型问题上踩坑

本项目的目标：构建一个 **嵌入 Spec-Driven Development（SDD）工作流的 agent 评审体系**，并让评审结论经治理后沉淀为团队记忆，回喂后续 coding 与 review，形成自我增强的飞轮。

## 2. 方案总览

两个互相咬合的子系统：

```
┌────────────────────────────────────────────────────────┐
│  A. 评审管线（agent-reviewer 本体）                      │
│  SDD 工作流（OpenSpec 式：changes/ + delta specs）       │
│  └─ 四个评审门禁：plan 评审 → 任务级评审 →                │
│     pre-commit hook 门禁 → PR/分支终审                   │
│  └─ reviewer = fresh-context subagent，                  │
│     输入 = diff + spec + 规则 + 团队记忆（四元组）         │
└──────────────┬───────────────────────────┬─────────────┘
               │ 评审结论（带证据链）         │ 消费历史记忆
               ▼                           ▼
┌────────────────────────────────────────────────────────┐
│  B. 团队记忆飞轮（ANDM, ai-native-dev-memory）           │
│  提炼 → quarantine（待审核）→ 审核入库 → 确定性召回注入    │
│  → 代码变更自动降级失效 → 重新审核                        │
└────────────────────────────────────────────────────────┘
```

- **A 是价值的直接来源**：把评审从 PR 阶段左移到开发循环内部，用门禁保证必然发生
- **B 是复利的来源**：每次评审让下一次评审更准

## 3. 核心设计决策（调研收敛，逐条有出处）

| # | 决策 | 依据 |
|---|---|---|
| D1 | 评审做成**机械门禁**（hook 拦截 + 工件校验），不做 prompt 建议 | 报告一 §4.3 / §5 |
| D2 | reviewer 用 **fresh-context subagent**，工件即接口，绝不给会话历史 | 报告一 §4.2（superpowers） |
| D3 | **双评审互补**：conformance（是否符合 spec）与 correctness（红队挑错）分开 | 报告一 §4.5（openkash） |
| D4 | 误报抑制：并行多维评审 → 验证 subagent 二次确认 → 高阈值过滤；不标风格问题 | 报告一 §3.4（官方 /code-review） |
| D5 | 确定性工程 × Agent 混合：文件选择/规则匹配/定位/过滤交给代码，LLM 只做判断 | 报告一 §3.5（OCR） |
| D6 | 记忆**治理优先于存储**：quarantine 状态机 + 证据链 + 代码版本绑定失效 | 报告二 §4；references/06 |
| D7 | 记忆召回走**确定性模块匹配**，语义检索只作补充；宁可漏召不可错召 | references/02、03 |
| D8 | 进程内编排用 subagent 派发，跨工具/跨团队才用 A2A 协议 | 报告二 §4.2 |
| D9 | 一切门禁 fail-open + 琐碎改动豁免 + 迭代熔断 | 报告一 §4.3 / §5 |

## 4. 落地路线图

### MVP（2–3 周，5–10 人试点）——评审最短闭环

交付物：

- SDD 骨架：OpenSpec 式 `changes/` 目录 + schema 插入 review 节点（报告一 §6.1）
- reviewer skill：负责任务级评审的 subagent 派发模板（D2/D3/D4）
- pre-commit 门禁：PreToolUse hook 拦截 `git commit`，要求评审工件与 diff hash 绑定（D1/D9）
- 记忆最短链路：评审结论 → quarantine → 人工审核 → 按模块注入 reviewer prompt（ANDM §6.1）

验收标准：

- 评审在 commit 前 100% 发生（非 PR 后）
- 平均每 PR 评审轮数 ≤ 2（超过即门禁太紧，需调豁免）
- quarantine 审核 SLA 内消化，积压趋零

### V1 —— 飞轮闭合

- 失效引擎：git hook 监听条目 `bound_paths`，代码变更自动降级（ANDM §5.3）
- coding 侧消费：生成 tasks 时注入 convention/api_usage 记忆（ANDM §5.2）
- session 综合写入 + 记忆蒸馏（同模块同类意见 ≥N 次 → 模块级规约）
- 评估体系：shadow 模式先行，A/B 对比有/无记忆注入的评审逃逸率（references/05）

### V2 —— 规模化

- severity 自动路由（low 自动入库 / high 必人审）
- trust 反馈自清洁 + 蜜罐回归测试（references/06）
- 跨工具 A2A 适配（Claude Code 产出交 Codex 复审等跨模型场景）
- CI 终闸：PR 级评审接现成工具（PR-Agent / Action）兜底
- 底座迁移评估：SQLite-vec → mem0/Graphiti（报告二 §2）

## 5. 度量体系（全程）

| 指标 | 用途 | 目标 |
|---|---|---|
| 评审漏网率 | 门禁松紧 | 趋零 |
| 每 PR 评审轮数 | review theater 信号 | ≤2 |
| **A/B：有/无记忆注入的逃逸缺陷率** | 北极星：飞轮价值证明 | 有记忆组显著更优 |
| 失效引擎漏检率 | 绑定代码已变更但未降级 | <3% |
| 真·误导率 | 记忆注入导致错误生成/误判 | <1%（一票否决） |
| 审核积压 / 误杀率 | 治理可持续性 | 积压趋零 / 误杀 <1% |

## 6. 主要风险与对策

| 风险 | 对策 |
|---|---|
| 陈旧记忆污染（飞轮反转） | 版本绑定失效 + trust 自清洁 + precision 优先（D6/D7） |
| Review theater 固化进记忆库 | 无 file:line 证据的条目不入 quarantine（D6） |
| 审核队列无人处理 | severity 路由 + agent 一审 + 人批量二审（ANDM §4.2） |
| 门禁被团队绕过 | fail-open + 豁免机制 + 误杀率监控（D9） |
| 记忆库成为注入面 | 写入只进 quarantine + 指令-数据隔离 + 蜜罐回归（references/06） |

## 7. 文档地图

| 文档 | 内容 |
|---|---|
| [docs/research/sdd-code-reviewer-landscape.md](docs/research/sdd-code-reviewer-landscape.md) | 调研一：SDD 框架 × 代码评审工具生态（OpenSpec、spec-kit、OCR、CodeFuse-Query、superpowers 等） |
| [docs/research/multi-agent-memory-communication-review.md](docs/research/multi-agent-memory-communication-review.md) | 调研二：多智能体记忆/通信方案事实核查（mem0/Graphiti/A2A 等选型依据） |
| [docs/design/ai-native-dev-memory-loop.md](docs/design/ai-native-dev-memory-loop.md) | 概念设计：记忆飞轮闭环与 prior-art 分析 |
| [docs/design/ai-native-dev-memory-architecture.md](docs/design/ai-native-dev-memory-architecture.md) | 系统设计：ANDM 架构、schema、状态机、接口面 |
| [docs/design/mvp-minimal-design.md](docs/design/mvp-minimal-design.md) | **MVP 最小设计**：4 组件契约、门禁脚本、评审工件格式、验收标准（动手起点） |
| [references/memory-engineering/](references/memory-engineering/) | 记忆工程机制笔记（检索/生命周期/压缩/评估/安全/生产架构） |
| [papers/](papers/) | 12 篇核心论文 PDF（LOGOS、Voyager、ExpeL、Microscope 等） |