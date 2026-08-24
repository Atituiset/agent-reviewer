# 补充卷论断级证据摘录

> 自动提取自 deep-research 工作流运行日志（2026-08-24，run wf_5e46c9ce-12a），收录《[landscape-supplement](landscape-supplement.md)》所引论断的原始表述、来源与原文引用片段，作为仓内可追溯的证据底稿。
> 多数论断经 3 票独立对抗验证（refuted:false）；被证伪与未走完投票的情况已在补充卷正文逐条标注。

## 检索线索（搜索阶段命中的来源）

### Does AI Code Review Lead to Code Changes? (arXiv case study)

- 来源: https://arxiv.org/html/2508.18771v2
- 摘要: 对 16 个开源 AI review GitHub Action 的实证研究，以 anc95/ChatGPT-CodeReview 为例拆解实现：YAML workflow 在 PR opened/reopened/synchronize 触发，base..head 累积 diff 逐文件审查、按 token 上限切块、仅以 diff 为上下文。提出按粒度分类法（PR-level / file-level inline / hunk-level line comment）与已审 commit 追踪去重等设计差异，并量化其对代码变更的实际影响——为报告的形态分类与效果局限提供数据支撑。

### CR-Bench: Evaluating the Real-World Utility of AI Code Review Agents

- 来源: https://arxiv.org/abs/2603.11078
- 摘要: 最直接的误报率实证数据：专为'误报代价高'场景设计的 benchmark。单次 agent（GPT-5.2）recall 仅 ~27% 而 precision 仅 ~3.56%（SNR 5.11）；加 Reflexion 多轮反思后 recall 升至 ~33% 但 SNR 跌到 1.95（小模型甚至跌到 0.91，幻觉压力导致噪声爆炸）。核心结论：'发现问题数'与'有效信号密度'存在结构性 trade-off，低 SNR 会通过频繁误报侵蚀开发者信任——直接支撑 SDD+reviewer 工作流中 gate 阈值与置信度过滤的设计依据（已验证 URL 真实）。

### "Go Home Copilot, You're Drunk": Understanding Developer Responses to Agent-Generated Code Review Comments

- 来源: https://arxiv.org/abs/2607.21997
- 摘要: 首个大规模 agent review 评论采纳研究：342 个 Python 仓库、~54,791 条来自 Copilot/Cursor/Codex/Devin/Claude 的评论。未采纳评论的十大模式中 'incorrect suggestions' 与 'intentional design decisions' 最普遍；并明确指出'更大的上下文窗口本身并不能保证上下文恰当的反馈'——直接反驳'堆 context 就能解决误报'的常见假设，对设计 reviewer 的 rubric（如区分作者有意的设计决策 vs 缺陷）极有参考价值。

### Automated Code Review In Practice (ICSE 2025 SEIP)

- 来源: https://arxiv.org/abs/2412.18531
- 摘要: 基于开源 Qodo PR-Agent 的工业案例（3 个项目，1,568/4,335 个 PR 被 AI review）：73.8% 的 AI 评论被处理，但 PR 平均关闭时间从 5h52m 涨到 8h20m；缺点包括错误评审、不必要的修改建议和离题评论拖慢流程。全文还报告了每 PR token 消耗/成本数据。这是'reviewer 接入工作流反而增加 cycle time + token 成本'这一反面证据的最佳来源，可用来论证 gate/checkpoint 应设在 SDD 哪些阶段而非全量触发。

### Understanding the Limits of Automated Evaluation for Code Review Bots (Beko industrial study)

- 来源: https://arxiv.org/html/2604.24525
- 摘要: 对 2,604 条 bot 生成的 PR 评论的工业研究：LLM-as-a-Judge/G-Eval 自动评估与人工标注仅达中等一致（0.44–0.62），不完美的评估器会放大 review 噪声、分散 reviewer 注意力并降低信任（alert fatigue）。建议自动评分只用于 triage 而非决策——对'SDD 各阶段用 LLM critic 做 spec/plan review 时如何定位其输出（辅助分流而非门禁裁决）'是关键教训。

### LLM Evaluators Recognize and Favor Their Own Generations

- 来源: https://arxiv.org/abs/2404.13076
- 摘要: 'reviewer 与作者同为 LLM 的共同盲区'的奠基性证据：GPT-4/GPT-3.5/Llama-2 都系统性偏爱自己生成的输出，且模型具备开箱即用的自我识别能力（GPT-4 达 73.5%，微调后 >90%），自我识别能力与自偏好强度呈线性相关。后续工作（EACL 2026 'Don't Judge Code by Its Cover'、rubric-based 自偏好研究显示即使客观 rubric 下判官仍可能高估自己失败的输出达 50%）表明该盲区难以靠换 prompt 根除——支撑报告中'用不同家族模型做 critic、authorship obfuscation、多 judg

### From Prompt to Process: A Process Taxonomy and Comparative Assessment of Frameworks Supporting AI Software Development Agents

- 来源: https://arxiv.org/html/2606.04967
- 摘要: 学术对比基线：用六维分类法（specification/context/roles/execution/validation/portability）评估 Spec Kit、OpenSpec、BMAD、GSD、Spec Kitty、Reversa 六个框架。validation 是独立维度（checklist、自动化测试、human review、readiness gates），并明确记录了各框架的 review 环节：Spec Kitty 要求 merge 前 review+acceptance、BMAD 有 PRD review/readiness check/code review、S

### metareview — Local-first review gates and learning for coding agents

- 来源: https://github.com/dsifry/metareview
- 摘要: 最直接回答“reviewer 接入 SDD 各阶段”的开源实现：为工作流每个决策点定义具名 gate（review artifact 审 spec/plan/架构/拆解的完整性与可测性、review task-done 审任务级代码、review epic-ready、review pr-ready、review learn 做事后沉淀），并给出结构化裁决契约（PASS / PASS_ADVISORY / NEEDS_REVISION / ESCALATED，critical+high 一律视为 blocker，exit code 强制执行）。spec/plan review 默认以并行 su

### Building a code review tool: The LLM patterns that actually work (G-Research)

- 来源: https://www.gresearch.com/news/building-a-code-review-tool-the-llm-patterns-that-actually-work/
- 摘要: 生产级 reviewer 的工程经验教训，直击误报率与 alert 疲劳：单 pass 约 8 条发现中 2-3 条误报，改为“recall pass + precision pass”两段式（第二段带误报示例做过滤）；结构化输出方面用 Pydantic JSON schema + 规则索引校验（模型不得发明不存在的规则），截断/校验失败的恢复策略，可确定推导的字段（severity）用代码算而非让 LLM 判；对非确定性评审做 severity 加权回归测试（MUST 规则 100% 召回、precision >85%、零误报容忍）；刻意不阻塞合并、保留人类裁量。

### review-spec SKILL.md — spec-conformance review skill (serpro69/claude-toolbox)

- 来源: https://github.com/serpro69/claude-toolbox/blob/master/klaude-plugin/skills/review-spec/SKILL.md
- 摘要: spec review 阶段的可借鉴 skill 设计：将实现代码与 design.md/implementation.md/tasks.md 逐条比对，输出六类类型化发现（MISSING_IMPL / EXTRA_IMPL / SPEC_DEV / DOC_INCON / OUTDATED_DOC / AMBIGUOUS），每条带 P0-P3 严重级（P0 阻塞合并）+ 1-10 置信度 + 强制证据推理；提供两种调用模式——标准模式跑在主会话（便宜）与 isolated 模式委托给零作者偏见的 spec-reviewer subagent（用于 pre-merge 等高要求场景，失败自动回

## 论断与原文引用

### In a large-scale empirical study of 16 popular LLM-based AI code-review GitHub Actions, only 0.9%-19.2% of val…

- 来源: (检索结果)
- 原文引用: "We analyzed 178 mature repositories and found a total of 22,326 AI-generated review comments. ... 60% of valid human review comments led to code changes ... compared to only 0.9%–19.2% for valid AI-generated comments depending on the tool"
- 论断全文: In a large-scale empirical study of 16 popular LLM-based AI code-review GitHub Actions, only 0.9%-19.2% of valid AI-generated review comments led to code changes, versus 60% for valid human review comments — quantifying the large effectiveness gap between AI and human reviewers (studied across 178 mature repositories with 22,326 AI-generated comments).

### Review granularity strongly affects whether developers act on AI review comments: hunk-level (diff-range) revi…

- 来源: (检索结果)
- 原文引用: "hunk-level review actions (6.5%–19.2%) exhibit a higher addressing rate compared to file-level actions (0.9%–4.2%)"
- 论断全文: Review granularity strongly affects whether developers act on AI review comments: hunk-level (diff-range) review actions achieved 6.5%-19.2% addressing rates versus 0.9%-4.2% for file-level comments, and PR-level comments were almost entirely ignored (only 1 of 30 sampled was partially addressed) — supporting hunk/diff-level review as the preferred integration granularity.

### Trigger mechanism matters: manually triggered AI reviews were acted on roughly 2x-44x more often than automati…

- 来源: (检索结果)
- 原文引用: "anc95/ChatGPT-CodeReview showed a 12.8% addressing rate for manually triggered comments versus 6.8% for automatically triggered ... the massive feedback resulting from unconditional triggering might reduce developers' willingness to respond"
- 论断全文: Trigger mechanism matters: manually triggered AI reviews were acted on roughly 2x-44x more often than automatically triggered ones (ChatGPT-CodeReview 12.8% manual vs 6.8% automatic; code-review-gpt 22.2% vs 0.5%), and the authors attribute this to unconditional triggering flooding developers with feedback.

### Most current AI code-review tools use a simplistic 'one-in-one-out' paradigm that emits comments on every PR r…

- 来源: (检索结果)
- 原文引用: "most current tools rely on a simplistic one-in-one-out paradigm ... This leads to low-precision output and reviewer fatigue. ... We observed many vague or unhelpful comments from tools with limited prompt context."
- 论断全文: Most current AI code-review tools use a simplistic 'one-in-one-out' paradigm that emits comments on every PR regardless of need, producing low-precision output and reviewer fatigue, including vague comments and hallucinated style warnings when prompt context is limited.

### The authors' recommendation for adopters is to position AI code review as a complement to human review rather …

- 来源: (检索结果)
- 原文引用: "for now, AI code review is better framed as a complement to human review, not a replacement"
- 论断全文: The authors' recommendation for adopters is to position AI code review as a complement to human review rather than a replacement, scoping AI reviewers to defensive-programming concerns while humans retain architecture and business-logic review — directly applicable to designing a reviewer checkpoint in an SDD workflow.

### 该论文（arXiv 2606.04967，2026-06-03 提交，作者 Sanderson Oliveira de Macedo，Federal Institute of Goias）提出一个六维流程分类法——Spe…

- 来源: (检索结果)
- 原文引用: ""How are errors detected before becoming deliverables?" ... indicators: "Tests, checklists, gates, artifacts, human review, confidence"; rubric anchors: "0 when the dimension is absent or incipient, 1 when it is partial, and 2 when it is strong or central.""
- 论断全文: 该论文（arXiv 2606.04967，2026-06-03 提交，作者 Sanderson Oliveira de Macedo，Federal Institute of Goias）提出一个六维流程分类法——Specification、Context、Roles、Execution、Validation、Portability——并用 0–2 分量表评估了六个开源 SDD 框架：GitHub Spec Kit、OpenSpec、BMAD Method、Get Shit Done (GSD)、Spec Kitty、Reversa；其中 Validation 维度直接对应研究问题中的 review/gate 环节。

### 在被评估的 SDD 框架中，只有部分框架内置了显式 review 检查点：BMAD Method 的验证环节包含 PRD 评审、就绪检查和代码评审（Validation 得分 2，总分 10/12 为样本内最高）；Spe…

- 来源: (检索结果)
- 原文引用: "BMAD validation includes "PRD review, readiness checks and code review." Spec Kitty's flow follows "spec, plan, tasks, next, review, accept and merge," using git worktrees with "review and acceptance before the merge.""
- 论断全文: 在被评估的 SDD 框架中，只有部分框架内置了显式 review 检查点：BMAD Method 的验证环节包含 PRD 评审、就绪检查和代码评审（Validation 得分 2，总分 10/12 为样本内最高）；Spec Kitty 的流程为 spec→plan→tasks→next→review→accept→merge，基于 git worktree 并在合并前做评审与验收（Validation 与 Execution 均得 2，总分 9）。

### 与用户计划参考的 OpenSpec 直接相关：论文给 OpenSpec 的 Validation 维度打 0 分（即缺失或仅萌芽状态），其轻量 slash-command/change-proposal 工作流没有内建 …

- 来源: (检索结果)
- 原文引用: "Spec Kit commands include "constitution, specification, plan, tasks and implementation" plus optional clarification, analysis and checklist commands; dominant risk is "Drift between artifacts and implementation if validation is weak." OpenSpec: lightweight SDD with slash commands and change proposals; validation scored 0."
- 论断全文: 与用户计划参考的 OpenSpec 直接相关：论文给 OpenSpec 的 Validation 维度打 0 分（即缺失或仅萌芽状态），其轻量 slash-command/change-proposal 工作流没有内建 review/gate；GitHub Spec Kit 的命令覆盖 constitution/specification/plan/tasks/implementation 加可选的 clarification、analysis、checklist，Validation 仅得 1 分，其主要风险是规格与实现之间的漂移。这意味着在 OpenSpec/Spec Kit 上接入 reviewer 属于需自行补齐的空白。

### 作为样本外验证的社区框架 Spec-Flow 展示了 gate/checkpoint 与多 agent critic 的具体组合模式：分层质量门 + 多 agent 投票 + 性能/安全/覆盖率扫描，并在流程完整度上得 …

- 来源: (检索结果)
- 原文引用: "Spec-Flow: spec/plan/tasks/implement/optimize/ship flow with "tiered quality gates, multi-agent voting and performance, security and coverage scans." ... "adoption (stars) and process completeness are orthogonal dimensions" ... "the traction filter selects by adoption and relevance, not by process completeness.""
- 论断全文: 作为样本外验证的社区框架 Spec-Flow 展示了 gate/checkpoint 与多 agent critic 的具体组合模式：分层质量门 + 多 agent 投票 + 性能/安全/覆盖率扫描，并在流程完整度上得 11/12（超过所有样本内框架），但其 GitHub star 数最低（85★ vs Spec Kit 106,786★），说明采用度与流程完备度正交。

### 论文的核心结论与局限：没有任何框架在六个维度上都达到强覆盖（"no framework strongly covers all six dimensions"），且存在流程深度与可移植性之间的结构性权衡；上下文缺失会导致…

- 来源: (检索结果)
- 原文引用: ""no framework strongly covers all six dimensions"; "There is a structural trade-off between process depth and portability." Agents can go "blind to context" in large repositories; absent context produces "functional hallucinations": "code that compiles, but violates implicit contracts.""
- 论断全文: 论文的核心结论与局限：没有任何框架在六个维度上都达到强覆盖（"no framework strongly covers all six dimensions"），且存在流程深度与可移植性之间的结构性权衡；上下文缺失会导致"功能性幻觉"（能编译但违反隐式契约的代码）；但论文未讨论 AI reviewer 的误报率、alert 疲劳或 token 成本（token 成本仅作为未来纵向研究的度量出现）。

### metareview implements review gates with an explicit four-outcome lifecycle contract — PASS, PASS_ADVISORY, NEE…

- 来源: (检索结果)
- 原文引用: "`NEEDS_REVISION`: fix blockers, then re-run the same gate with `--previous-run <run-id>`. ... `ESCALATED`: stop same-target retries; human must narrow, split, or redesign the target."
- 论断全文: metareview implements review gates with an explicit four-outcome lifecycle contract — PASS, PASS_ADVISORY, NEEDS_REVISION, and ESCALATED — where NEEDS_REVISION requires re-running the same gate with --previous-run <run-id> and ESCALATED stops same-target retries and forces human intervention to narrow, split, or redesign the target.

### metareview runs artifact reviews through five required adversarial reviewer lenses (architecture, code quality…

- 来源: (检索结果)
- 原文引用: "Artifact review runs the five required lenses as parallel subagents by default ... `in-session-emulated` fallback is weaker evidence and must say the review is not independently adversarial."
- 论断全文: metareview runs artifact reviews through five required adversarial reviewer lenses (architecture, code quality, security, test adequacy, product/user impact) executed as parallel subagents by default, and treats an in-session-emulated fallback as weaker evidence that must disclose it is not independently adversarial.

### metareview places distinct review gates at each SDD workflow stage — specs, plans, code, epics, PRs, and post-…

- 来源: (检索结果)
- 原文引用: ""Local-first review gates and learning for specs, plans, code, epics, PRs, and post-merge follow-up.""
- 论断全文: metareview places distinct review gates at each SDD workflow stage — specs, plans, code, epics, PRs, and post-merge — exposed as Claude Code slash commands (/review-artifact, /review-task-done, /review-epic-ready, /review-pr-ready, /learn-post-merge) and Codex skills ($-prefixed equivalents), triggered by agent/human invocation at checkpoints rather than CI webhooks.

### metareview includes a post-merge learning loop (`learn --post-merge`) that extracts durable lessons from merge…

- 来源: (检索结果)
- 原文引用: "extract durable lessons from merged work, review feedback, failures, and session history into local knowledge. ... metareview keeps this learning local, nonproprietary, and user-readable"
- 论断全文: metareview includes a post-merge learning loop (`learn --post-merge`) that extracts durable lessons from merged work, review feedback, failures, and session history into a local, git-syncable Markdown/JSONL knowledgebase, pruning stale entries so subsequent reviews start with accumulated calibration — addressing reviewer blind-spot/repeat-mistake problems without a hosted service.

### metareview ships as both a standalone npm CLI (Go-backed binary) and as plugins installed via marketplace into…

- 来源: (检索结果)
- 原文引用: "Unlike proprietary SaaS review products such as CodeRabbit, Greptile, and similar hosted reviewers"
- 论断全文: metareview ships as both a standalone npm CLI (Go-backed binary) and as plugins installed via marketplace into Claude Code and Codex CLI, demonstrating a dual host-form-factor integration pattern (in-harness skill/plugin plus independent tool) positioned explicitly against hosted SaaS reviewers like CodeRabbit and Greptile; it is MIT-licensed with only ~9 stars and 28 commits (initial public release May 27, 2026, latest commit Aug 15, 2026), indicating early-stage adoption.

### The open-source serpro69/claude-toolbox project ships a `review-spec` Claude Code skill (invoked as `/kk:revie…

- 来源: (检索结果)
- 原文引用: "Use after implementing tasks or mid-feature to verify code matches design docs and ensure they are in sync."
- 论断全文: The open-source serpro69/claude-toolbox project ships a `review-spec` Claude Code skill (invoked as `/kk:review-spec [feature-name]`) that performs spec-conformance review — comparing implementation code against design/implementation/task docs — usable both mid-feature (on completed tasks) and post-implementation, demonstrating a spec-review checkpoint embedded in a skill-based SDD workflow.

### The skill prescribes a bidirectional review rubric with six machine-readable finding-type codes (MISSING_IMPL,…

- 来源: (检索结果)
- 原文引用: "Findings go in **both directions** — code that deviates from spec AND spec that is wrong or outdated given the code."
- 论断全文: The skill prescribes a bidirectional review rubric with six machine-readable finding-type codes (MISSING_IMPL, EXTRA_IMPL, SPEC_DEV, DOC_INCON, OUTDATED_DOC, AMBIGUOUS) covering deviations of code from spec AND of spec/docs from code, rather than one-directional code-only review.

### The skill offers an isolated mode (`/kk:review-spec:isolated`) that delegates detection to a separate `spec-re…

- 来源: (检索结果)
- 原文引用: "Delegates detection to an independent `spec-reviewer` sub-agent that did not write the code, then annotates its findings with type-specific author context. ... Isolation: True — reviewer has zero authorship bias or session context"
- 论断全文: The skill offers an isolated mode (`/kk:review-spec:isolated`) that delegates detection to a separate `spec-reviewer` subagent which did not author the code, explicitly to remove authorship bias — a concrete subagent/critic pattern addressing the reviewer-author-same-LLM blind spot; it falls back to standard mode if the subagent fails and is recommended for post-implementation, pre-merge.

### Findings use structured output designed as a merge gate: a P0–P3 severity scale where P0/P1 block merge, plus …

- 来源: (检索结果)
- 原文引用: "**P0** | Critical | Missing core functionality, security spec violated, data model mismatch ... Must fix before merge ... Each finding gets a confidence score (1–10) with **mandatory reasoning**"
- 论断全文: Findings use structured output designed as a merge gate: a P0–P3 severity scale where P0/P1 block merge, plus a mandatory 1–10 confidence score with required reasoning per finding (9–10 = certain direct contradiction, 1–2 = speculative) to suppress low-confidence noise.

### The skill enforces process ordering and an ownership boundary: the reviewer must load spec docs and complete p…

- 来源: (检索结果)
- 原文引用: "**Mandatory order — spec before code.** The flow below is strictly sequential. ... Indexing is owned by this skill — callers (e.g., `/kk:implement`) do NOT duplicate it."
- 论断全文: The skill enforces process ordering and an ownership boundary: the reviewer must load spec docs and complete profile detection before reading any implementation code (only a filename listing is allowed early), and confirmed intentional SPEC_DEV/EXTRA_IMPL findings are indexed into a shared `kk:arch-decisions` knowledge store owned solely by the review skill so callers like `/kk:implement` do not duplicate indexing.

## 验证记录摘录（对抗核实结论）

### V1 · refuted=False

Primary source verified directly. arXiv abs page (https://arxiv.org/abs/2606.04967) confirms: title "From Prompt to Process: a Process Taxonomy and Comparative Assessment of Frameworks Supporting AI Software Development Agents", sole author Sanderson Oliveira de Macedo, submitted June 3, 2026, abstract stating the contribution is "a six-dimension process taxonomy: specification, context, roles, execution, validation and portability". The HTML ver

### V2 · refuted=False

Primary source verified by two independent fetches of https://arxiv.org/html/2606.04967v1 ("From Prompt to Process: a Process Taxonomy and Comparative Assessment of Frameworks Supporting AI Software Development Agents", de Macedo, 03 Jun 2026). Table 6 gives OpenSpec Validation = 0 (rubric: "0 = absent or incipient"; total 6) and GitHub Spec Kit Validation = 1 ("partial"; total 8), exactly as claimed. Section 5 confirms Spec Kit commands "constit

### V3 · refuted=False

Verified directly against the primary source (arXiv:2606.04967v1, "From Prompt to Process", dated 03 Jun 2026). Every specific element of the claim matches the paper exactly. (1) Verbatim quotes confirmed: Section 4 contains "BMAD, PRD review, readiness checks and code review"; Spec Kitty's declared flow follows "spec, plan, tasks, next, review, accept and merge" and "Spec Kitty places review and acceptance before the merge" using git worktrees. 

### V4 · refuted=False

Verified directly against the primary source (arXiv 2606.04967v1, https://arxiv.org/abs/2606.04967 and https://arxiv.org/html/2606.04967v1). Every element of the claim checks out: (1) Paper exists: "From Prompt to Process: a Process Taxonomy and Comparative Assessment of Frameworks Supporting AI Software Development Agents", sole author Sanderson Oliveira de Macedo, byline affiliation "Federal Institute of Goias" (also confirmed by his dblp entry

### V5 · refuted=False

Verified against the primary source (arXiv HTML full text, https://arxiv.org/html/2606.04967v1) and the abstract page (https://arxiv.org/abs/2606.04967). Every element of the claim checks out: (1) The paper exists — "From Prompt to Process: a Process Taxonomy and Comparative Assessment of Frameworks Supporting AI Software Development Agents", arXiv:2606.04967, cs.SE/cs.AI, submitted Wed 3 Jun 2026 (v1), single author Sanderson Oliveira de Macedo,

### V6 · refuted=False

Primary source verified directly: arXiv:2606.04967v1 ("From Prompt to Process...", Sanderson Oliveira de Macedo, submitted 2026-06-03) contains every load-bearing element of the claim. Table 6 scores OpenSpec Validation=0 and Spec Kit Validation=1; the rubric defines 0="absent or incipient" and 1="partial", matching the claim's parenthetical "缺失或仅萌芽状态". The paper states Spec Kit organizes "constitution, specification, plan, tasks and implementati

### V7 · refuted=False

Verified the primary source directly: arXiv:2606.04967 ("From Prompt to Process: a Process Taxonomy and Comparative Assessment of Frameworks Supporting AI Software Development Agents", Macedo, v1 dated 03 Jun 2026) exists and contains both the quoted content and the exact scores. Section 4 states "Spec Kit brings analysis and checklist commands; BMAD, PRD review, readiness checks and code review"; Section 5 describes Spec Kitty following "spec, p

### V8 · refuted=False

Verified against the primary source (arXiv 2606.04967v1, "From Prompt to Process...", dated 03 Jun 2026): Table 6 scores OpenSpec Validation=0 and GitHub Spec Kit Validation=1 on its 0-2 rubric where 0="absent/incipient"; Section 5 confirms Spec Kit organizes "commands such as constitution, specification, plan, tasks and implementation" plus "optional clarification, analysis and checklist commands"; Table 5 lists Spec Kit's dominant risk as "Drif

### V9 · refuted=False

Primary source verified and claim matches it exactly. arXiv 2606.04967 ("From Prompt to Process: a Process Taxonomy and Comparative Assessment of Frameworks Supporting AI Software Development Agents", Sanderson Oliveira de Macedo, submitted 03 Jun 2026) evaluates six frameworks (Spec Kit, OpenSpec, BMAD, GSD, Spec Kitty, Reversa). Table 6 scores match the claim precisely: BMAD Method Validation=2, total 10/12 (highest in sample); Spec Kitty Valid

### V10 · refuted=False

Verified directly against the primary source (arXiv:2508.18771v2, "Does AI Code Review Lead to Code Changes? A Case Study of GitHub Actions", Sun/Kuang/Baltes/Zhou/Zhang/Ma/Rong/Shao/Treude). Every element of the claim matches the paper verbatim: (1) "large-scale empirical study of 16 popular AI-based code-review actions for GitHub workflows"; (2) "Out of 718 matched repositories, 178 met the maturity criterion" (>=50 PRs); (3) "these contained a

### V11 · refuted=False

Verified directly against the primary source (arXiv:2508.18771v2, "Does AI Code Review Lead to Code Changes? A Case Study of GitHub Actions" by Sun, Kuang, Baltes, Zhou, Zhang, Ma, Rong, Shao, Treude). Every number in the claim matches the paper verbatim: (1) abstract states "a large-scale empirical study of 16 popular AI-based code-review actions for GitHub workflows"; (2) Discussion states "0.9%–19.2% for valid AI-generated comments depending o

### V12 · refuted=False

Verified directly against the primary source (arXiv:2508.18771v2, "Does AI Code Review Lead to Code Changes? A Case Study of GitHub Actions"). Every figure in the claim matches the paper exactly: (a) abstract describes "a large-scale empirical study of 16 popular AI-based code-review actions for GitHub workflows" with all 16 named in Table II (e.g., coderabbitai/ai-pr-reviewer, anc95/ChatGPT-CodeReview, mattzcarey/code-review-gpt); (b) "Out of 71

### V13 · refuted=False

Verified directly against the primary source (raw README fetched live from https://raw.githubusercontent.com/dsifry/metareview/main/README.md on 2026-08-21). The README section "Lifecycle gate results have a small operating contract" lists exactly four outcomes in order: PASS, PASS_ADVISORY, NEEDS_REVISION, ESCALATED. Verbatim: NEEDS_REVISION — "fix blockers, then re-run the same gate with `--previous-run <run-id>`"; ESCALATED — "stop same-target

### V14 · refuted=False

Verified directly against the primary source (arXiv:2508.18771v2, published as IEEE TSE 2026, DOI 10.1109/TSE.2026.3688237 — peer-reviewed, not just a preprint). Table XIII (Fisher's Exact Test) reports exactly the claimed numbers: anc95/ChatGPT-CodeReview 12.8% addressing rate manual (n=86) vs 6.8% auto (n=1,595), p≤0.05; mattzcarey/code-review-gpt 22.2% manual (n=18) vs 0.5% auto (n=602), p≤0.05. The 'roughly 2x-44x' framing is arithmetically f

### V15 · refuted=False

All three factual components verified verbatim against the primary source (arXiv 2508.18771v2, "Does AI Code Review Lead to Code Changes? A Case Study of GitHub Actions"): (1) RQ2 states "hunk-level review actions (6.5%–19.2%) exhibit a higher addressing rate compared to file-level actions (0.9%–4.2%)" (Table IX: coderabbitai 19.2%, aidar-freeed 6.5% vs ChatGPT-CodeReview 4.2%, code-review-gpt 0.9%); (2) the paper reports randomly investigating 3

### V16 · refuted=False

Verified directly against the primary source (arXiv:2508.18771v2, "Does AI Code Review Lead to Code Changes? A Case Study of GitHub Actions"). Table XIII reports exactly the claimed figures: anc95/ChatGPT-CodeReview 12.8% addressing rate manually triggered (n=86) vs 6.8% automatically triggered (n=1,595), p≤0.05; mattzcarey/code-review-gpt 22.2% manual (n=18) vs 0.5% auto (n=602), p≤0.05. The ratios match "roughly 2x-44x" (1.9x and 44.4x). The ca

### V17 · refuted=False

Verified against full text of arXiv:2508.18771v2 ("Does AI Code Review Lead to Code Changes? A Case Study of GitHub Actions", Sun/Kuang/Baltes/Zhou/Zhang/Ma/Rong/Shao/Treude, v2 dated 25 Apr 2026). All elements check out: (1) Verbatim passage confirms ChatGPT-CodeReview numbers: "anc95/ChatGPT-CodeReview showed a 12.8% addressing rate for manually triggered comments versus 6.8% for automatically triggered ones." Table XIII confirms both actions w

### V18 · refuted=False

Verified verbatim against the primary source README (https://raw.githubusercontent.com/dsifry/metareview/main/README.md). The README contains a section titled "Lifecycle gate operating contract" listing exactly four outcomes: "PASS: proceed.", "PASS_ADVISORY: proceed only when the review reports zero blocking findings.", "NEEDS_REVISION: fix blockers, then re-run the same gate with `--previous-run <run-id>`.", and "ESCALATED: stop same-target ret

### V19 · refuted=False

Verified against the primary source (arxiv.org/html/2508.18771v2, "Does AI Code Review Lead to Code Changes? A Case Study of GitHub Actions"). All three numeric components of the claim are accurate: (1) The RQ2 answer states verbatim "hunk-level review actions exhibit a higher addressing rate (6.5%–19.2%) compared to file-level actions (0.9%–4.2%)"; per-tool Table IX confirms coderabbitai/ai-pr-reviewer at 19.2% and aidar-freeed/ai-codereviewer a

### V20 · refuted=False

Verified against the primary source (https://github.com/dsifry/metareview README, v0.6.0). Every component of the claim checks out: (1) Gates per stage — README tagline verbatim: "Local-first review gates and learning for specs, plans, code, epics, PRs, and post-merge follow-up"; use-cases list distinct gates for spec review, plan review, architecture/feasibility review, decomposition & fractal child-plan (epic) review, code review ("task-sized c

### V21 · refuted=False

Verified against the primary source (arXiv:2508.18771v2, "Does AI Code Review Lead to Code Changes? A Case Study of GitHub Actions", Sun et al., Nanjing Univ.). The supporting quote appears verbatim in the paper's Answer to RQ2: "hunk-level review actions (6.5%–19.2%) exhibit a higher addressing rate compared to file-level actions (0.9%–4.2%)" (continuing: "...still lags behind human review comments (60%)"). Per-tool breakdown confirms the ranges

### V22 · refuted=False

Verified against the primary source's raw README (https://raw.githubusercontent.com/dsifry/metareview/main/README.md). Every element of the claim checks out verbatim: (a) tagline "Local-first review gates and learning for specs, plans, code, epics, PRs, and post-merge follow-up" confirms the per-stage gates; (b) README states "Claude Code invokes metareview through /setup, /review-task-done, /review-epic-ready, /review-pr-ready, /review-artifact,

### V23 · refuted=False

Claim verified against primary source and implementation code. The metareview README (main branch) states verbatim: "Lifecycle gate results have a small operating contract: `PASS`: proceed. `PASS_ADVISORY`: proceed only when the review reports zero blocking findings. `NEEDS_REVISION`: fix blockers, then re-run the same gate with `--previous-run <run-id>`. `ESCALATED`: stop same-target retries; human must narrow, split, or redesign the target." — 

### V24 · refuted=True

The claim's mechanics are verified, but its enumeration of the five lenses is contradicted by the project's own canonical definition — a material factual error. VERIFIED parts: (a) README states verbatim "Artifact review runs the five required lenses as parallel subagents by default; `in-session-emulated` fallback is weaker evidence and must say the review is not independently adversarial." (b) skills/review-artifact/SKILL.md line 15-16 confirms:
