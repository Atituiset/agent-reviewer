# 调研补充卷：实证有效性数据 · 同类项目补遗 · MVP 设计勘误

> 版本：v0.1 · 2026-08-24
> 定位：《SDD 工作流集成 Agent Code Reviewer》主报告（[sdd-code-reviewer-landscape.md](sdd-code-reviewer-landscape.md)，下称「报告一」）的补充卷。只列**增量与勘误**，不重复报告一内容。
> 产出方式：与报告一相互独立的第二路调研——deep-research 工作流（5 路并行检索 → 抓取核心来源 → 每条论断 3 个独立验证代理对抗核实），共 107 个子代理、约 570 次工具调用。报告一由 KIMI K3 独立完成，两路调研的**交集本身构成跨模型交叉验证**；本卷同时给出报告一的查漏结果。
> 票型标注：〔已验证〕= 经 3 票对抗核实（refuted:false 且证据逐字核对原文）；〔未走完验证〕= 检索阶段提取、因限流未完成投票，引用前建议点开原文复核。

---

## 0. TL;DR

1. **报告一最大的结构性缺口是缺定量实证**：§5 教训表全部是定性引述。本卷补入 5 组同行评议/大规模实证数据（§1），其中三条直接影响 MVP 设计参数（file:line 锚定、置信度阈值、≤2 轮熔断）。
2. **漏掉两个同定位开源项目**（§2）：metareview 几乎就是本项目「形态 B」的现成先例（四态门禁生命周期 + 双宿主分发 + post-merge 学习回喂）；review-spec 的六类双向 finding 码可直接抄进 MVP conformance 通道。
3. **一篇 2026-06 分类法论文**（§3）给报告一 §2.4 的横向对比提供了学术佐证（OpenSpec Validation 维度得 0 分），且其 12 分量表可直接用来给 MVP/V1 自评。
4. **MVP 设计两处具体漏洞 + 一处文档不一致**（§5）：diff_hash 口径（staged vs index）、评审工件并发覆盖、verdict 二态缺熔断出口、README 四道门禁 vs MVP 两道。

---

## 1. 实证有效性数据（报告一 §5 的定量补充）

### 1.1 AI 评审评论的实际采纳率——file:line 锚定是硬要求，不是风格偏好 〔已验证〕

[arXiv:2508.18771](https://arxiv.org/abs/2508.18771)《Does AI Code Review Lead to Code Changes?》（南京大学 / 海德堡 / 拜罗伊特）：16 个流行 AI review GitHub Actions、178 个成熟仓库（≥50 PR）、22,326 条 AI 生成评论：

- 有效 AI 评论最终导致代码修改的比例仅 **0.9%–19.2%**，人类有效评论为 **60%**
- **粒度是最大变量**：hunk 级评论 6.5%–19.2%，文件级仅 0.9%–4.2%，PR 级几乎全被忽略（30 条采样仅 1 条被部分处理）
- 最佳工具（coderabbitai/ai-pr-reviewer）19.2%，最差（mattzcarey/code-review-gpt）0.9%

**对本项目的意义**：MVP §2.3「每条 finding 必须 file:line 锚定」由此从工程习惯升级为**有 5–10 倍效果差异支撑的实证要求**。建议写入报告一 §4.9 模式 4 的论据，以及 reviewer prompt 模板的硬约束说明。

### 1.2 评论未解决的头号原因：缺设计上下文，而非事实错误 〔未走完验证〕

[arXiv:2607.21997](https://arxiv.org/abs/2607.21997)：54,791 条 agent 评审评论（Copilot / Cursor / Codex / Devin / Claude 五个 agent）、342 个 Python 仓库：

- 解决率分化明显：Copilot 72.9% / Cursor 67.2% / Codex 54.8%
- 对 470 条未解决线程做卡片分类得十类模式，头两名：**Intentional Design Decision（112 例）＞ Incorrect Suggestion（67 例，其中 63 条事实错误、4 条幻觉）**

**意义**：「agent 不知道项目的意图设计」造成的无效评论多于模型能力不足。这是报告一 §6.3.1「spec 作为评审输入」机会点的**定量证明**——该痛点是真实的、可测的，且是第一优先级。

### 1.3 接入评审的代价：cycle time 与 token 成本 〔未走完验证〕

[arXiv:2412.18531](https://arxiv.org/abs/2412.18531)《Automated Code Review In Practice》（ICSE 2025 SEIP，Beko + Bilkent 大学，238 人软件部门）：

- CodeReviewBot（基于 Qodo PR-Agent + GPT-4 Turbo）在 10 个项目 22 仓库中的 3 个深潜项目落地：4,335 个 PR 中 1,568 个被 AI 评审
- **73.8% 的 AI 评论被开发者处理**，但 **PR 平均关闭时间从 5h52m 升到 8h20m**（p<0.001，项目间异质）；缺点记录：错误评审、不必要的修改建议、离题评论
- 每 PR 约 3,937 token ≈ $0.48
- 关键细节：Beko 用的是**硬门禁**——每条 bot 评论必须被显式处置（fix 或 wontFix）才允许合并

**意义**：(a) 评审不是免费的，gate 放在哪个阶段、豁免怎么设计直接决定 cycle-time 代价——支持报告一「评审左移但带豁免」的立场；(b) README「平均每 PR 评审轮数 ≤2」的阈值有了外部参照系；(c) Beko 的 disposition-before-merge 是本项目 gate 哲学的真实工业同构先例。

### 1.4 信噪比边界：多轮反思提召回、降精度 〔部分验证〕

[arXiv:2603.11078](https://arxiv.org/abs/2603.11078)（CR-Bench / CR-Evaluator）：专为「误报代价高」场景设计的 code review agent 基准：

- 单轮 agent（GPT-5.2）：recall ~27%，precision 仅 ~3.56%（信噪比 5.11）
- 加 Reflexion 多轮自我批判：recall 升至 ~33%，**但 SNR 跌至 1.95**（更小模型跌至 0.91——幻觉压力放大噪声）
- 核心论点：「解决真实问题」与「产生虚假发现」之间存在隐藏的权衡边界（frontier）——reviewer 不能同时最大化召回和精确

**意义**：MVP 的两个取舍方向被独立基准印证——「只报 ≥80 置信度」（牺牲 recall 保 precision）、「红队候选 → 独立验证 subagent 二次确认」。同时提示：**不要为了提 recall 无限加反思轮数**，SNR 会反向恶化。

### 1.5 自动评分的天花板：只配做分诊，不配做裁决 〔未走完验证〕

[arXiv:2604.24525](https://arxiv.org/abs/2604.24525)（同为 Beko 工业数据，2,604 条 bot 评论）：LLM-as-judge / G-Eval 自动评分与人工 fixed/wontFix 标注的一致率仅 **0.44–0.62**（Gemini-2.5-pro / GPT-4.1-mini / GPT-5.2 × 二元 / Likert rubric 组合）：

- **Likert（0–4）分级 rubric 一致率稳定高于二元 yes/no**；最佳配置 G-Eval + Likert + GPT-4.1-mini = 0.62
- 作者结论原话："Use automated evaluation for triage, not decision-making"

**意义**——对 MVP §2.4.2 场景回放协议的三条直接约束：

1. rationale 语义判等的 judge 天花板就在 ~0.6，回放结论应定位为 **triage 信号**（哪里要改 prompt），不能当验收线
2. golden 比对的 judge 输出应用**分级评分**而非二元判等（与 Likert 优势一致）
3. 报告一 §4.8「LLM 清单」类 gate 的局限又添一层：不仅生成端不可靠，评判端同样有上限

### 1.6 同模型自偏好：fresh context 不等于消除偏见 〔未走完验证〕

[arXiv:2404.13076](https://arxiv.org/abs/2404.13076)《LLM Evaluators Recognize and Favor Their Own Generations》：

- 同模型既当作者又当评委时系统性偏爱自己输出（GPT-4 两两比较偏好分 XSUM 0.705 / CNN-DailyMail 0.912）
- 模型具备开箱即用的自我识别能力（GPT-4 达 73.5%，微调后 >90%），**自偏好强度与自识别能力线性相关**（GPT-3.5 上 Kendall tau 0.41→0.74）——偏见源于认出「自己写的」，而非质量差异
- 后续工作（EACL 2026 "Don't Judge Code by Its Cover" 等）显示即使客观 rubric 下判官仍可能高估自己失败的输出达 50%，换 prompt 难以根除

**意义**：D2（fresh-context subagent）消除的是**会话上下文偏见**，不消除**模型自偏好**——同一模型审自己风格的代码仍会放水。缓解三件套：① critic 用不同家族模型；② authorship 匿名化（不给 reviewer 会话历史恰好是其一）；③ 多 judge ensemble。这为 V2「跨工具 A2A 适配（Claude 产出交 Codex 复审）」提供了定量依据，建议提升优先级。

---

## 2. 同类项目补遗（报告一遗漏的两个直接同类物）

### 2.1 dsifry/metareview——形态 B 的现成先例 〔已验证〕

仓库 [dsifry/metareview](https://github.com/dsifry/metareview)（v0.6.0）。自述："Local-first review gates and learning for specs, plans, code, epics, PRs, and post-merge follow-up"——与本项目定位几乎重合。报告一只字未提，建议补入 §3/§4：

- **双宿主分发即形态 B 的活样本**：同一套门禁同时以 Claude Code slash commands（`/setup` `/review-task-done` `/review-epic-ready` `/review-pr-ready` `/review-artifact` `/learn-post-merge` `/status`）和 Codex `$skills`（`$setup` 等）暴露；本体是本地 CLI，编码 agent 把它当作 completion gate 调用，不走 CI webhook
- **四态门禁生命周期**（比 MVP 的二态成熟）：
  - `PASS` / `PASS_ADVISORY`（带非阻塞意见通过）
  - `NEEDS_REVISION`：修复 blocker 后**带 `--previous-run <run-id>` 重跑同一 gate**（跨 run 可追溯）
  - `ESCALATED`：**禁止同目标继续重试**，人工必须收窄、拆分或重新设计目标——熔断后的显式出口
- **五个必选对抗 lens**（以其 `rubrics/artifact-review-rubric.md` 为准）：Feasibility / Completeness / Scope & alignment / Architecture / Intent preservation——注意这是**工件层**视角，与报告一 §4.5 的代码层 conformance/correctness 正交，两层可以叠用
- 默认五个 lens 以并行 subagent 执行；回退到 in-session 自审时必须声明「本次评审非独立对抗」——弱证据显式降级的表述值得抄
- `/learn-post-merge`：合并后学习回喂后续评审——**ANDM 记忆飞轮在门禁层的先行者**

> 诚实性注记：验证阶段曾**证伪**一条对该项目五 lens 的错误枚举（初稿误作 architecture/code quality/security/test adequacy/product impact，四个错四个）——以 rubric 原文为准。这本身是对抗验证流程价值的现场示范。

### 2.2 serpro69/claude-toolbox 的 review-spec skill——报告一 §6.3.1「空白」的先行者 〔未走完验证〕

[SKILL.md 原文](https://github.com/serpro69/claude-toolbox/blob/master/klaude-plugin/skills/review-spec/SKILL.md)：`/kk:review-spec [feature-name]` 做 spec-conformance 评审（对照 design/implementation/task docs 检查代码），mid-feature 与 post-implementation 均可用，另有 isolated 隔离模式。最有价值的是**双向六类机器可读 finding 码**：

```
MISSING_IMPL   # spec 有、代码没有
EXTRA_IMPL     # 代码有、spec 没有（scope creep）
SPEC_DEV       # 刻意偏离 spec（应有依据）
DOC_INCON      # 文档内部不一致
OUTDATED_DOC   # spec/doc 过时于代码（反向 finding！）
AMBIGUOUS      # 无法判定
```

**意义**：

1. 报告一 §6.3.1 称「结构化 conformance 评审只有小项目以 prompt 方式做了」——review-spec 就是那个先行者，**空白表述应收窄**为：「与 OpenSpec delta-spec 结构深度整合 + 与机械门禁联动」尚无现成实现（这部分判断仍成立）
2. 六类码可直接抄进 MVP conformance 通道的输出 schema——尤其 `OUTDATED_DOC` 反向通道（spec 过时于代码）是 delta-spec 维护的关键输入，报告一的评审模式全是单向的（代码对照 spec），漏了这个方向

### 2.3 Planner–Generator–Evaluator harness 模式 〔未走完验证〕

[Agent Patterns Catalog: Planner-Generator-Evaluator Harness](https://www.agentpatternscatalog.org/patterns/planner-generator-evaluator-harness/)：把长时程 agent 工作拆成三个角色隔离的 agent——Planner 产计划工件 / Generator 每个 chunk 用全新上下文 / **Evaluator 按固定 rubric 打分且看不到 Generator 的执行轨迹**，返回 pass/fail + 结构化 findings；固定 rubric 使 Evaluator 行为跨 run 可复现。

**意义**：给 MVP 的 controller / implementer / task-reviewer 分工一个可引用的模式名与出处；也再次论证「reviewer 输入必须是工件而非对话历史」（D2）不只是防偏见，还是可复现性的前提。可与报告一 §4.9 合并为第九条模式。

---

## 3. 学术分类法补遗

### 3.1 arXiv:2606.04967 六维流程分类法——报告一 §2.4 结论的学术佐证 〔已验证〕

[arXiv:2606.04967](https://arxiv.org/abs/2606.04967)《From Prompt to Process》（2026-06-03，Federal Institute of Goias）：提出 Specification / Context / Roles / Execution / **Validation** / Portability 六维分类法，0–2 分制（0 缺失、1 局部、2 强）评估六个开源 SDD 框架（Table 6）：

| 框架 | 总分 /12 | Validation | 备注 |
|---|---|---|---|
| BMAD Method | **10** | 2 | 验证环节含 PRD 评审、就绪检查、代码评审；样本内最高 |
| Spec Kitty | 9 | 2 | 见 §3.2 |
| GitHub Spec Kit | 8 | 1 | 主要风险：validation 弱导致工件与实现漂移 |
| OpenSpec | 6 | **0** | 轻量 slash-command/change-proposal 流程无内建 review/gate |
| Reversa | 6 | 1 | 仅经 confidence/gap 标签做部分验证 |
| Get Shit Done | 4 | 0 | |

Validation 维度的指导问题即「错误如何在成为交付物之前被发现？」，指标包括 tests / checklists / gates / artifacts / human review / confidence。

**意义**：

1. 报告一的核心判断（OpenSpec 无内建评审、各家验证强度分化）获得**独立学术佐证**，建议在 §1/§2.4 加引
2. **更有用的用法**：直接拿这套 12 分量表给 MVP/V1 **自评打分**写进设计文档（如 README §4 各阶段旁标注目标得分），Validation 维度六个指标天然就是评审体系 checklist

### 3.2 补三个报告一未覆盖的分类法样本框架 〔已验证〕

- **Spec Kitty**：流程 `spec → plan → tasks → next → review → accept → merge`，基于 git worktree，**合并前强制评审 + 验收**——六个框架里 Validation 得满分的两家之一，也是与本项目「worktree + 门禁」路线最接近的开源框架，值得单独调研一轮
- **BMAD**：报告一 §2.3 说它「无可执行门禁全靠自觉」——分类法视角补充：其验证**流程**完备度是样本内最高（PRD 评审 + 就绪检查 + 代码评审），弱在可执行性。两种口径并存才是完整表述
- GSD / Reversa：样本内最低分梯队，暂无深入价值，知道存在即可

### 3.3 引用警示：一条已被源码证伪的常见表述 〔已证伪〕

「PR-Agent 每个工具都是单次 LLM 调用（~30 秒、低成本）」流传甚广（README 原文如此），但**与其自身源码矛盾**：`pr_agent/tools/pr_code_suggestions.py` 中 `/improve` 在建议调用之外还有一次强制的 self-reflection 第二次调用（代码注释标明 mandatory），大 PR 还会按 chunk 放大调用次数。报告一若日后引用 PR-Agent 成本数据，勿用这句 README 表述。

---

## 4. 小补充（各一句话，可并入报告一对应章节）

- **G-Research 内部 LLM 评审工具的两招**（[官方博客](https://www.gresearch.com/news/building-a-code-review-tool-the-llm-patterns-that-actually-work/)，未走完验证）：① severity 不让模型打分，由规则里的 RFC 2119 关键词（MUST/SHOULD/MUST NOT）**确定性推导**；② 对 finding 引用的规则 ID 做**存在性校验**——「LLM 会引用不存在的规则」。后者直接适用于 MVP `rules/scenarios/` 的 checklist 引用与 finding 的 `scenario` 字段校验
- **Spec Kit 官方扩展机制明确定位就包含评审**（已验证）：extensions 可添加「实现后代码评审」，presets 可「在 plan 中加强制安全评审 gate + 强制 test-first 任务排序」——报告一 §2.3 说 Spec Kit「无内容级可执行验证」没错，但可补一句「官方预留了 reviewer 插槽」，说明接入点是一等公民
- **人类介入点设计的参考文章**：[justinmchase.com: Spec-Driven Development – Keeping Humans in the Loop While Scaling AI-Assisted Code Review](https://justinmchase.com/2026/06/04/spec-driven-development-keeping-humans-in-the-loop-while-scaling-ai-assisted-code-review/)，与报告一 §4.1 的高杠杆点论述互补

---

## 5. MVP 设计勘误与建议（针对 mvp-minimal-design.md）

### 5.1 diff_hash 口径漏洞：staged ≠ committed 【建议修复】

现状：hook 在 PreToolUse 拦截 `git commit` 时，`verify-artifact.sh` 校验 `.review/last-review.json.diff_hash == sha256(git diff HEAD)`。但 `git diff HEAD` = staged + unstaged，而 **commit 只提交 index 内容**。

后果：部分 stage（`git add src/a.go` 而 src/b.go 也有改动未 stage）时，「评审过的树 ≠ 实际提交的树」——hash 绑定形同虚设，未评审的 b.go 改动随提交溜进门禁。

修法二选一（推荐前者，纯 shell 可实现）：

1. verify-artifact.sh 增加前置校验：`git diff --quiet`（无 unstaged 残留）否则拒审并提示先全部 stage
2. hash 改算 index 树：评审打包与校验统一用 `git write-tree` 的 tree SHA

### 5.2 评审工件并发覆盖 【建议修复】

`.review/last-review.json` 是全局单文件：同仓库两个 Claude 会话并行工作时互相覆盖工件，A 会话刚通过的评审会被 B 会话的旧工件顶掉（或反之），hash 校验随机失效。报告一 §4.4 的 codex-review 已给出先例：状态放 `.git/` 内**按会话隔离**。

修法：工件路径带会话标识（如 `.git/review-gate/<session-id>.json`），hook 从环境变量或 hook stdin 取当前会话 ID；`.review/metrics.jsonl` 保持全局 append-only 即可。

### 5.3 verdict 二态 → 三态：给熔断一个显式出口 【建议采纳】

现契约 `CLEAN | ISSUES_FOUND` 在「2 轮熔断触发但仍剩 findings」时没有出口语义——按 §3 主流程只能反复提示，实际使用必然演变成口头豁免。借 §2.1 metareview 的生命周期，改为：

```
CLEAN          # 全清，正常放行
ISSUES_FOUND   # 有未清 findings，继续修
ESCALATED      # 熔断触发：剩余 findings 降级 advisory 写入 metrics，
               # 工件上标记 escalated=true + 逐条 human_ruling，
               # commit 放行但留痕（呼应 superpowers 的 parked-with-ruling：
               # "a silent discard is forbidden"）
```

### 5.4 README 四道门禁 vs MVP 两道的分期标注 【文档一致性】

README §2 承诺四道门禁（plan 评审 → 任务级 → pre-commit → PR 终审），MVP 只落地任务级 + pre-commit 两道。而 §1.2/报告一 §4.1 的证据恰恰说 **plan 级是最便宜的一道**（devloop："Fixing a wrong abstraction in a plan costs minutes; in code, hours"）。二选一：

- 轻做法：README §4 MVP 交付物处明确标注「本期落地任务级 + pre-commit 两道，plan 评审 V1」
- 或 MVP 后段补轻量 `/sdd-review-plan`：完全复用 task-reviewer 模板与双通道纪律，输入包从 diff.patch 换成 proposal.md/design.md/tasks.md 三工件，产出直接进 quarantine（conformance 类 finding 如 MISSING_IMPL 用 §2.2 六类码）

---

## 6. 合并指引（本卷 → 既有文档）

| 本卷 | 去向 | 动作 |
|---|---|---|
| §1.1–1.6 定量实证 | 报告一 §5 表格扩充 / README §3 决策依据 | 给 D2/D4/D9 及「file:line」「≤2 轮」补数据出处 |
| §2.1 metareview | 报告一 §4 新小节 + §6.2 形态 B 参照 | 四态生命周期、双宿主分发、learn-post-merge |
| §2.2 review-spec | 报告一 §6.3.1 收窄表述 + MVP §2.3 输出 schema | 抄六类 finding 码（含反向 OUTDATED_DOC） |
| §2.3 PGE 模式 | 报告一 §4.9 第九条 | 模式命名 + 出处 |
| §3.1 分类法 | 报告一 §2.4 加引 + README 加自评量表 | Validation 六指标当 checklist |
| §3.2 Spec Kitty 等 | 报告一 §2.2/§2.3 | 补行 + BMAD 双口径表述 |
| §3.3 PR-Agent 证伪 | 报告一 附录 B 存疑项 | 引用警示 |
| §4 小补充 | 报告一 §2.3/§3.5/附录 A | RFC2119 定 severity、规则 ID 校验、extensions 定位 |
| §5.1–5.4 | mvp-minimal-design.md §2.1/§2.2/§2.3 + README §4 | 建议下一版 MVP 文档落实 |

---

## 附录 A：本卷新增信源

> 本地留存：七篇实证论文 PDF 已入库 `papers/`（命名 `*-arxiv-<id>.pdf`）；metareview README 与 review-spec SKILL.md 快照见 `references/primary-sources/`；本卷所引论断的原始表述与原文引用片段见 [landscape-supplement-evidence.md](landscape-supplement-evidence.md)（自动提取自工作流日志）。

**实证研究**
- [arXiv:2508.18771] Does AI Code Review Lead to Code Changes? A Case Study of GitHub Actions
- [arXiv:2607.21997] Agent 评审评论解决率大规模研究（54,791 条评论 / 342 仓库）
- [arXiv:2412.18531] Automated Code Review In Practice（ICSE 2025 SEIP，Beko 工业部署）（[会议页](https://conf.researchr.org/details/icse-2025/icse-2025-software-engineering-in-practice/8/Automated-Code-Review-In-Practice)）
- [arXiv:2604.24525] Understanding the Limits of Automated Evaluation for Code Review Bots
- [arXiv:2603.11078] CR-Bench: Evaluating the Real-World Utility of AI Code Review Agents
- [arXiv:2404.13076] LLM Evaluators Recognize and Favor Their Own Generations
- [arXiv:2606.04967] From Prompt to Process: SDD 框架六维分类法

**项目与文章**
- [dsifry/metareview](https://github.com/dsifry/metareview) · [serpro69/claude-toolbox review-spec SKILL.md](https://github.com/serpro69/claude-toolbox/blob/master/klaude-plugin/skills/review-spec/SKILL.md)
- [Planner-Generator-Evaluator Harness](https://www.agentpatternscatalog.org/patterns/planner-generator-evaluator-harness/)
- [G-Research: Building a Code Review Tool – the LLM Patterns That Actually Work](https://www.gresearch.com/news/building-a-code-review-tool-the-llm-patterns-that-actually-work/)
- [justinmchase.com: Keeping Humans in the Loop While Scaling AI-Assisted Code Review](https://justinmchase.com/2026/06/04/spec-driven-development-keeping-humans-in-the-loop-while-scaling-ai-assisted-code-review/)

## 附录 B：存疑项与本卷边界

1. 标〔未走完验证〕的论断（§1.2/1.3/1.5/1.6/§2.2/§2.3/§4 G-Research）来自检索提取，验证投票因 API 限流未完成；数字均照录原文摘要，引用前建议点开原文复核
2. 一条未并入正文的检索说法：`openspec validate` 除格式校验外还检查 spec-task 对齐（orphan task 检测）——与已知的格式/schema 校验语义有出入，疑为版本演进所致，待本地实测后再决定是否并入报告一 §1.1
3. metareview 迭代快（v0.6.0，2026-06 尚在活跃开发），生命周期与 lens 清单引用请注意版本
4. 本卷 star 数一律未引（增长极快，无引用价值）；报告一附录 B 的时效性警示继续适用
