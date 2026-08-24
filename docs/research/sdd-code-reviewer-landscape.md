# SDD 工作流集成 Agent Code Reviewer：业内实践调研报告

> 调研日期：2026-08-21
> 调研方式：6 路并行子代理深度检索（GitHub API / 官方文档 / 工程博客 / arXiv），所有 star 数为调研当日 GitHub API 实测或 shields.io 缓存值（已分别标注）
> 调研范围：以 GitHub 开源项目为主，商业闭源产品（CodeRabbit、Greptile、Kiro、Tessl）作为模式参考
> 调研动机：计划做一个参考 OpenSpec（SKILL.md / slash-command 式 SDD 工作流框架）的项目，并在工作流中接入 agent code reviewer

---

## 0. TL;DR

业内已收敛出一个核心共识：**评审必须是流水线上的「机械门禁（gate）」，而不是写在 prompt 里的「建议」**。`CLAUDE.md` 类指令是建议性的（约 80% 遵守率），hooks 是确定性的（100% 执行）——这一「advisory vs deterministic」的区分是所有实现的分水岭。

被反复验证的最佳形态：

1. SDD 每个阶段（spec → plan → tasks → implement）之间插入由**独立上下文 reviewer subagent** 执行的评审节点；
2. 关键节点（如 commit 前）用 **hook 强制拦截**；
3. 评审结论以**带 diff hash 的持久化工件**落地，抗 context compaction；
4. 设**迭代上限熔断** + 争议仲裁机制，防止无限 review 循环（review theater）；
5. 误报抑制靠「并行多维评审 → 验证 subagent 二次确认 → 高阈值过滤」。

---

## 1. OpenSpec 深度拆解（本项目的主要参照系）

仓库：[Fission-AI/OpenSpec](https://github.com/Fission-AI/OpenSpec)，约 **65,745 stars**（2026-08-21 GitHub API 实测），fork ~4.5k，创建于 2025-08-05。TypeScript，MIT，npm 包 `@fission-ai/openspec`（Node ≥ 20.19.0）。README 自称 "The most loved spec framework"。

定位哲学（README 原文关键词）：`fluid not rigid / iterative not waterfall / easy not complex / built for brownfield not just greenfield / scalable from personal projects to enterprises`。官方自述对比：vs Spec Kit「更轻、可自由迭代，无刚性阶段门禁」；vs Kiro「不锁定 IDE 和模型」。

### 1.1 两层架构：CLI（引擎）+ Slash Commands（方向盘）

- **CLI（终端层）**：`openspec init`、`openspec list`、`openspec view`、`openspec validate`、`openspec archive`、`openspec status`、`openspec instructions`——负责初始化、校验、列出/归档 change、dashboard
- **Slash commands（聊天层）**：在 AI 助手聊天框中输入，指示 AI 执行 SDD 工作流，**不是终端命令**。`openspec init` 把这些命令以 skill/命令文件形式装进 AI 工具——即「终端层安装聊天层」

### 1.2 Slash Commands / Skills 体系

**新版 OPSX 命令**（当前主推，"artifact-guided workflow"），默认 core profile 装 5 个：

| 命令 | 作用 |
|---|---|
| `/opsx:explore` | 探索性对话：读代码、比较方案，不产生 artifact，可转入 propose |
| `/opsx:propose <name>` | 一步创建 change 并生成全部规划 artifact（proposal、specs、design、tasks） |
| `/opsx:apply` | 按 `tasks.md` 逐项实现，勾选 `[x]`，可断点续做 |
| `/opsx:sync` | 把 change 的 delta specs 合并进主 `openspec/specs/`（archive 时通常自动提示） |
| `/opsx:archive` | 归档：检查任务完成度 →（可选）sync delta specs → 移到 `changes/archive/YYYY-MM-DD-<name>/` |

扩展 profile（`openspec config profile` 选择后 `openspec update` 应用）额外提供：`/opsx:new`（只建脚手架 + `.openspec.yaml` 元数据）、`/opsx:continue`（按依赖图生成下一个 artifact）、`/opsx:ff`（一次生成全部）、**`/opsx:verify`**（从 completeness/correctness/coherence 三维度验证实现与 spec 一致性，报告 CRITICAL/WARNING/SUGGESTION）、`/opsx:bulk-archive`、`/opsx:onboard`（交互式教学）。

**旧版 Legacy 命令**（仍兼容）：`/openspec:proposal` / `/openspec:apply` / `/openspec:archive`，"all-at-once" 工作流。旧版 proposal 流程：读 `openspec/project.md` → `openspec list` 看活跃 change → 脚手架 proposal/tasks/design → 写 spec deltas → `openspec validate --strict`。

### 1.3 目录约定与 spec 格式（棕地友好的关键）

```
openspec/
├── specs/                    # source of truth：系统当前如何工作，按 domain 分目录
│   └── auth/spec.md, payments/spec.md, ...
├── changes/                  # 提议中的修改，每个 change 一个文件夹，可并行
│   └── add-dark-mode/
│       ├── proposal.md       # Why：intent、scope、approach
│       ├── design.md         # How：技术方案、架构决策
│       ├── tasks.md          # 实现清单（1.1/1.2 分层编号 + checkbox）
│       ├── .openspec.yaml    # change 元数据（schema、可选 skip_specs: true）
│       └── specs/            # delta specs：相对主 spec 的增量
│           └── ui/spec.md
├── changes/archive/YYYY-MM-DD-<name>/   # 归档，完整保留审计线索
└── config.yaml               # schema + context + 按 artifact 的 rules
```

- **Spec 格式**：纯 Markdown，`## Purpose` / `### Requirement:`（RFC 2119 的 SHALL/MUST/SHOULD）/ `#### Scenario:`（Given/When/Then）。spec 是「行为契约」，不放实现细节
- **Delta spec 机制**：change 里的 spec 用 `## ADDED Requirements` / `## MODIFIED Requirements` / `## REMOVED Requirements` 描述「改了什么」而非全量 spec；archive 时合并进主 `specs/`——「两个 change 可以改同一个 spec 文件，只要动的是不同 requirement，就不冲突」
- **Schema 机制**：workflow 由 `schema.yaml` 定义 artifact 依赖图。内置默认 `spec-driven`：`proposal → (specs ∥ design) → tasks → implement`，依赖是「enabler 不是 gate」。可用 `openspec schema init/fork` 自定义——**这是插入自定义 review 阶段的官方机制**。解析优先级：CLI `--schema` > change 的 `.openspec.yaml` > `openspec/config.yaml` > 默认

### 1.4 完整流程节奏

1. 可选 `/opsx:explore`——先想清楚
2. `/opsx:propose add-dark-mode` → 创建 change，生成全部 artifact，**此时不写代码，人审计划**
3. `/opsx:apply` → AI 读 `tasks.md` 逐项实现并勾选 `- [x]`，可中断续做
4. 可选 `/opsx:verify` → 检查实现与 spec 的漂移
5. `/opsx:archive` → delta specs 合并进主 specs（sync），change 移入 archive——"Specs grow organically as changes are archived"

### 1.5 与 AI 编码 agent 的集成机制

**当前机制（Skills + Commands）**：`openspec init` 按所选工具生成两类文件——

- **Skills**（跨工具标准，一个文件夹 + `SKILL.md`，agent 自动探测）：`.claude/skills/openspec-*/SKILL.md`、`.cursor/skills/`、`.codex/skills/`（Codex 是 skills-only）等；生成的 skill 名如 `openspec-propose`、`openspec-apply-change`、`openspec-verify-change`、`openspec-archive-change` 等 12 个
- **Commands**（per-tool slash 命令文件）：`.claude/commands/opsx/<id>.md`、`.cursor/commands/opsx-<id>.md`、`.github/prompts/opsx-<id>.prompt.md`、`.gemini/commands/opsx/<id>.toml` 等

支持 **34 个工具 ID**：claude、cursor、windsurf、github-copilot、codex、gemini、cline、kilo、roocode、opencode、qwen、kimi、trae、kiro、auggie、factory、continue、amazon-q、iflow、junie、codebuddy 等。各工具调用语法不同：Claude Code 用冒号 `/opsx:propose`；Cursor/Windsurf/Copilot 用连字符 `/opsx-propose`；Codex 用 `$openspec-propose`；Kimi CLI 用 `/skill:openspec-propose`；Amazon Q 用 `@opsx-propose`。

**AGENTS.md / CLAUDE.md 注入机制的演变**（易被旧文章误导，按仓库归档 change 考据）：

1. 初版：`openspec init` 在 `CLAUDE.md` 插入 marker 块（`<!-- OPENSPEC:START/END -->`），完整指令模板放在 `openspec/AGENTS.md`
2. 2025-09-29：marker 机制扩展到根级 `AGENTS.md` 标准
3. 2025-10-14：根级文件瘦身为指向 `openspec/AGENTS.md` 的短 stub，防止内容漂移
4. OPSX 改版后（当前）：技能化，**AGENTS.md/CLAUDE.md marker 注入整体移除**；旧的 `openspec/project.md` 被 `openspec/config.yaml` 的 `context:` 取代，且 context 是**主动注入到每次规划请求的 instructions 里**（而非被动等 AI 去读），按 artifact 还有 `rules:` 字段

即集成思路从「被动等 AI 读规则」转向「主动注入上下文」。

**其他**：Stores（beta）跨 repo 共享 spec；项目自身 dogfooding（`openspec/changes/archive/` 有真实历史）；遥测默认开启可关（`OPENSPEC_TELEMETRY=0`）；init 默认 `delivery: both`（skills + commands）。升级路径：升级 npm 包 → 项目里跑 `openspec update`。

**源码关键位置**：`src/core/init.ts`（`WORKFLOW_TO_SKILL_DIR` 映射）、`src/core/config.ts`（`AI_TOOLS`、`OPENSPEC_MARKERS`）、`src/core/templates/workflows/*.ts`（各 skill 模板）、`src/core/legacy-cleanup.ts`（旧配置清理）。

---

## 2. SDD 生态格局

### 2.1 业内坐标系

Martin Fowler 网站 Birgitta Böckeler 系列（[martinfowler.com](https://martinfowler.com/articles/exploring-gen-ai/sdd-3-tools.html)）给出公认分层：

- **spec-first**：先写规格再生成代码（绝大多数工具在此层）
- **spec-anchored**：规格随功能长期维护、与代码同步演进
- **spec-as-source**：规格即源码，代码完全由 AI 生成

### 2.2 主要项目速览（star 为 2026-08-21 GitHub API 实测）

| 项目 | 仓库 | Stars | 性质 | SDD 层级 | 内置评审/验证强度 |
|---|---|---|---|---|---|
| GitHub Spec Kit | [github/spec-kit](https://github.com/github/spec-kit) | ~130.6k | 开源 MIT，Python CLI | spec-first | `/speckit.analyze` 只读跨工件一致性分析；exit-code 门禁仅查文件存在性 + 人工 TTY 审批 |
| OpenSpec | [Fission-AI/OpenSpec](https://github.com/Fission-AI/OpenSpec) | ~65.7k | 开源 MIT，TS CLI | spec-first/anchored | `/opsx:verify` 三维度验证（建议性） |
| superpowers | [obra/superpowers](https://github.com/obra/superpowers) | ~275k（引用前建议复核） | 开源，skill 框架 | spec-first | **最强任务级评审**：fresh implementer + 独立 reviewer 双评审 + 全分支终审 |
| BMAD-METHOD | [bmad-code-org/BMAD-METHOD](https://github.com/bmad-code-org/BMAD-METHOD) | ~52.1k | 开源 MIT | spec-first（方法论框架） | QA 产出 PASS/CONCERNS/FAIL gate 文件，全靠 agent 自觉 |
| Agent OS | [buildermethods/agent-os](https://github.com/buildermethods/agent-os) | ~5.3k | 开源 MIT，纯 shell+markdown | v3 已退出完整管线 | **无门禁无验证** |
| cc-sdd | [gotalab/cc-sdd](https://github.com/gotalab/cc-sdd) | ~3.6k | 开源 MIT，npm | spec-first（Kiro 复刻） | 每任务独立 reviewer + TDD + auto-debug |
| AWS Kiro | [kiro.dev](https://kiro.dev) | 商业（Code OSS fork） | 闭源 | spec-first | **最强可执行验证**：EARS → property-based testing；可阻断 hooks |
| Tessl | [tessl.io](https://tessl.io) | 商业（$125M 融资，估值 $500M+） | 闭源 | **spec-anchored / spec-as-source** | spec↔实现人工审批 + 链接测试 |

### 2.3 逐项目详情

**GitHub Spec Kit**（品类事实标准）：`uv tool install specify-cli`，`specify init --integration claude` 生成 `.specify/`。工作流：`/speckit.constitution`（项目"宪法"，不可变高层原则）→ `/speckit.specify` → `/speckit.clarify` → `/speckit.plan` → `/speckit.tasks` → **`/speckit.analyze`** → `/speckit.implement`；另有 `/speckit.checklist`、`/speckit.taskstoissues`、`/speckit.converge`。30+ agent 集成（slash commands 或 `--skills` 模式）；extensions/presets/bundles 三级定制。评审强度（源码级调研结论）：`check-prerequisites.sh` 是 exit-code 门禁但只查**文件存在性**；gate 步骤是 TTY 人工 approve/reject（CI 中退化为 PAUSED）；`/speckit.analyze`、`/speckit.checklist` 是 LLM 解释的 markdown 清单——**存在性门禁 + 人工审批 + LLM 清单，无内容级可执行验证**。官方 extensions/presets 的定位示例即包含「添加实现后代码评审」「在 plan 中加强制安全评审 gate + 强制 test-first 任务排序」——reviewer 接入点是一等公民插槽，缺的是内容级验证本体【v0.1 增补】。

**AWS Kiro**（方法论源头）："requirements → design → tasks" 三阶段范式的原创者。产物三件套：`requirements.md`（用户故事 + **EARS 记法**验收标准）、`design.md`、`tasks.md`；对 tasks 构建依赖图分 wave 并行执行。差异化亮点：**property-based testing**——把 EARS 需求翻译成可执行规格，自动生成性质测试校验生成代码。Hooks：`.kiro/hooks/*.json`，10 种触发器含 `PostFileSave`、**可阻断的 `PreToolUse` / `UserPromptSubmit` / `PreTaskExec`**；动作分 shell command 与 agent prompt 两类。Steering 文件（product.md/structure.md/tech.md）充当 memory bank。

**Tessl**（spec-as-source 激进赌注，Snyk 创始人 Guy Podjarny）：两个产品——Spec Registry（"npm for specs"，10,000+ 开源库 usage spec，防 agent 幻觉 API 用法）与 Tessl Framework（spec 三段式：组件描述 + 带链接测试的 capabilities + `{.api}` 公开接口块；`@generate ./src/index.ts` 驱动代码生成，生成文件头标注 `// GENERATED FROM SPEC - DO NOT EDIT`；当前 spec↔代码 1:1 映射）。spec 与实现间保留人工审批；自己不跑 agent，"坐在 agent 之上"提供 specs/skills/tests/governance。Fowler 作者警示：spec-as-source 类似当年 MDD，可能同时继承 MDD 的不灵活与 LLM 的非确定性。

**BMAD-METHOD**（"模拟敏捷组织"）：`npx bmad-method install`。角色化多 agent 管线：Analyst（brief）→ PM（PRD）→ Architect（架构）→ Scrum Master（拆 story）→ Dev → QA，产物以模板化 markdown 交接。v6 模块化生态：12+ 角色、34+ workflow，含 BMad Test Architect 和 **BMad Loop**（无人值守 build/verify/retro 整个 epic）。**无可执行门禁**——清单和交接全靠 agent 按 prompt 自觉执行（注意口径区分【v0.1 增补】：流程完备度上其验证环节含 PRD 评审、就绪检查、代码评审，是 arXiv:[2606.04967](https://arxiv.org/abs/2606.04967) 样本内最高分——BMAD 弱在可执行性而非流程缺失）。批评：角色 prompt 并不产生独立专业能力，角色间传文本可能放大早期错误假设（"cargo cult" 风险）。

**Agent OS**（已转型）：Brian Casel 出品，纯 shell 安装器 + markdown。**v3（2026-01）大幅收缩**：删除 v1/v2 的 write-spec/create-tasks/implement-tasks/orchestrate-tasks 和 subagent 框架，理由"Claude Code 的 plan mode 和更强的模型已覆盖这些脚手架"。当前仅 5 个命令：`discover-standards`（**从既有代码库逆向提取编码规范**——招牌能力）、`index-standards`、`inject-standards`、`plan-product`、`shape-spec`（增强 Plan Mode）。无门禁、无验证、无持久化 spec。

**cc-sdd**（Kiro 开源复刻）：`npx cc-sdd@latest`，支持 **8 个编码 agent × 13 种语言**，每平台同一套 **17 个 Agent Skills**（渐进式披露加载）。工作流（v3.0）：`/kiro-discovery`（分流：扩展 spec / 直接实现 / 单 spec / 多 spec）→ `/kiro-spec-init` → requirements → design → tasks → **`/kiro-impl`（长时程自主实现）**。产物带 EARS 格式、Mermaid 图、`_Boundary:_`/`_Depends:_` 任务标注。评审在小项目中罕见地完整：**每任务起一个全新 implementer subagent（TDD RED→GREEN + feature flag），配独立 reviewer；reviewer 连续两次拒绝或 implementer 卡住时触发 auto-debug**；跨任务通过 `tasks.md` 的 `## Implementation Notes` 传递经验；`/kiro-spec-batch` 多 spec 并行 + 跨 spec 审查矛盾；`/kiro-validate-gap` 存量系统差距分析。

### 2.4 横向对比结论

- **阶段划分**：requirements → design → tasks → implement 骨架是 Kiro 原创；cc-sdd 原样继承；Spec Kit 扩展为 7 阶段；BMAD 包装成角色化敏捷组织；Agent OS v3 放弃管线；Tessl 不做阶段管线
- **产物格式**：几乎全部 repo 内 markdown（+yaml）；Tessl 的 spec 是唯一带"可编译"语义的格式
- **Agent 集成**：Spec Kit slash commands/skills 覆盖最广（30+）；cc-sdd 走 Agent Skills + 各平台 subagent 原语；Kiro 版本化 JSON hooks；OpenSpec CLI 生成 34 工具的 skills+commands
- **评审/验证真实强度排序**：Kiro（可执行性质测试）> cc-sdd / superpowers（独立上下文复审流派，prompt 驱动）> Spec Kit（存在性门禁 + 人工审批 + LLM 清单）> Tessl（人工审批）> BMAD（自觉）> Agent OS（无）
- **学术佐证**【v0.1 增补】：[arXiv:2606.04967](https://arxiv.org/abs/2606.04967) 六维流程分类法（Specification/Context/Roles/**Validation**/Execution/Portability，0–2 分制）评估六框架：BMAD 10/12、Spec Kitty 9、Spec Kit 8、OpenSpec 6（**Validation=0**）、Reversa 6、GSD 4——OpenSpec 无内建 review 的判断获独立佐证；该量表可直接用于本项目自评（详见[补充卷 §3](landscape-supplement.md)）。分类法样本中的 Spec Kitty（`spec→plan→tasks→next→review→accept→merge`，git worktree，合并前强制评审验收）与本报告未覆盖，值得单独调研

### 2.5 各家独立收敛出的共识

引自 [vanja.io 的九框架源码阅读](https://vanja.io/265000-stars/)：先规划后写码；把意图持久化在 repo（聊天记录不是项目状态）；激进拆分小任务；用全新上下文做有界工作；**实现与评审分离**；以证据（跑过的测试）而非声明来验证；人类在高杠杆点（计划批准）介入。

---

## 3. 代码评审工具生态

### 3.1 开源工具总览

| 工具 | 仓库 | Stars | 形态 | 触发时机 | 输出 | 自定义规则 |
|---|---|---|---|---|---|---|
| **OpenCodeReview (OCR)** | [alibaba/open-code-review](https://github.com/alibaba/open-code-review) | 21,044（API） | Go CLI（`ocr`）+ GitHub Action + 多 agent skill/plugin + VSCode 扩展 | CLI 手动 / Action（PR）/ 宿主 agent slash 命令 | 行级结构化 JSON + PR 评论（sticky summary + incremental 去重） | `rule.json`（glob + 自然语言，四层优先级）+ `--background` 注入需求背景 |
| PR-Agent | [The-PR-Agent/pr-agent](https://github.com/The-PR-Agent/pr-agent) | ~12.6k | Action / CLI / Docker / App | PR opened/synchronize、push、评论命令 | inline + summary + 可选 Checks | `.pr_agent.toml` |
| reviewdog | [reviewdog/reviewdog](https://github.com/reviewdog/reviewdog) | ~9.5k | linter 输出 → 评审评论管道，CLI + Action | CI 事件 | inline review / Checks，可控 blocking | `.reviewdog.yml` |
| Danger / Danger JS | [danger/danger](https://github.com/danger/danger) / [danger-js](https://github.com/danger/danger-js) | ~5.7k / ~5.5k | CI 步骤，「规则即代码」 | CI 运行时（通常 PR） | PR 汇总评论（fail/warn/message），可 blocking | `Dangerfile` / `dangerfile.ts` |
| claude-code-action | [anthropics/claude-code-action](https://github.com/anthropics/claude-code-action) | ~8.7k | GitHub Action | 任意 workflow 事件 | 顶层评论 + inline（MCP）+ 进度追踪 | workflow YAML `prompt:` + CLAUDE.md |
| aider | [Aider-AI/aider](https://github.com/Aider-AI/aider) | 48,371（API） | CLI 内嵌反思循环 | 每次编辑后自动 lint/test | 非零退出码触发同会话自修复 | `--lint-cmd` / `--test-cmd` |
| Kodus (Kody) | [kodustech/kodus-ai](https://github.com/kodustech/kodus-ai) | ~1.3k | 独立 reviewer 平台，BYOK | PR 原生集成 + CLI + CI | inline + 自然语言规则 | 自定义规则 |
| remorses/critique | [remorses/critique](https://github.com/remorses/critique) | 1,254（API） | diff TUI + `critique review` | CLI 手动 | diff 交给 agent 解释 | 附 skill 文件 |
| critique-review | [repath500/critique-review](https://github.com/repath500/critique-review) | 0（结构典型） | SKILL.md + 按需 rubric | agent 加载 skill | P0–P3 分级 findings | `references/review-rubric.md` |
| CodeFuse-Query | [codefuse-ai/CodeFuse-Query](https://github.com/codefuse-ai/CodeFuse-Query) | 356（API；上游近一年停更） | 数据中心化静态分析平台（非 LLM 工具）：COREF 数据模型 + Gödel DSL + Sparrow CLI | CLI 手动 / CI（`--sarif` 输出） | 确定性分析结果（json/csv/sqlite/SARIF） | GDL 规则脚本（声明式、必然终止） |

**排除项/纠误**：TIGER-AI-Lab/Critique-Coder 是 ICLR 2026 RL 训练论文项目，非评审工具；"coder-critique" 精确名仓库不存在；contains-studio/agents 实际不含 code-reviewer（常见误传）；gitbito/codereviewagent（67 star）不达阈值；Sweep（[sweepai/sweep](https://github.com/sweepai/sweep)，~7.7k）已停更转型 JetBrains 插件，仅作历史参考。

### 3.2 重点开源工具详情

**PR-Agent**（开源自托管首选）：仓库沿革 Codium-ai → qodo-ai → 现捐赠社区迁至 The-PR-Agent（同一 repo id）。Slash commands：在 PR 评论中 `/describe`、`/review`、`/improve`、`/ask`、`/test`、`/update_changelog`、`/custom_prompt`。自动化：`[github_action_config]` 段 `auto_review / auto_describe / auto_improve`，`pr_actions = ['opened','reopened','ready_for_review','review_requested']`；`[github_app]` 段 `handle_push_trigger` 支持 push 增量评审。输出：review summary、labels、安全审查、`/improve` 行内可提交建议；v0.39+ `publish_as_check_run`；v0.40 `persistent_inline_comments` 防重复。自定义：`.pr_agent.toml`（`use_repo_settings_file=true` 默认开启）、组织级配置、每工具 `extra_instructions`、`[best_practices].content`；v0.39 起默认注入 `AGENTS.md`/`CLAUDE.md`（`repo_context_files`），支持 Agent Skills（SKILL.md）。模型经 LiteLLM 可换 OpenAI/Claude/Gemini/Bedrock/Ollama 等。

**reviewdog**：本身不是 AI，是「linter 输出 → 代码托管平台评审评论」的通用管道。reporters：`github-pr-review`（inline）、`github-pr-check`/`github-check`（Annotations，可 blocking）、`gitlab-mr-discussion` 等；exit code 可控（`fail_level`）。输入格式：errorformat、RDFormat（rdjson/rdjsonl，支持 severity、suggestions）、checkstyle、SARIF。

**Danger / Danger JS**：「formalize your PR etiquette」——用代码编写评审惯例（检查 CHANGELOG、PR 描述、anti-pattern）。DSL 四类：`fail`（可 blocking）/ `warn` / `message` / `markdown`；支持 inline comments。

**claude-code-action**：官方 Action，跑在自己 runner，`/install-github-app` 一键安装。触发完全由 workflow 定义：`pull_request: [opened, synchronize]` 自动评审、`paths:` 过滤、`if: author_association == 'FIRST_TIME_CONTRIBUTOR'`、@claude mention、cron、手动。输出经 prompt 指定：`Bash(gh pr comment:*)` 顶层评论、`mcp__github_inline_comment__create_inline_comment` inline、`track_progress: true` 进度追踪评论。无专用规则文件，规则全写 `prompt: |`（官方示例含 OWASP 安全评审模板），`claude_args: --allowedTools` 收敛工具权限。

**aider**（执行信号即评审范式）：无独立 reviewer 进程，评审即执行反馈——每次编辑后自动 lint（`--lint-cmd`，可按语言配置 `--lint "language: cmd"`），linter 约定「错误打印 stdout/stderr 且返回非零退出码」；`--test-cmd` + `--auto-test` 每次编辑后跑测试，非零退出触发自动修复。细节：README 建议用「跑两次 pre-commit」的 wrapper 区分「格式化改动」与「真实 lint 错误」。输入是执行信号而非语义评审；输出直接回同一会话修复，无人机闭环。

**remorses/critique**：主体是 Tree-sitter 高亮的 diff TUI；`critique review [--agent claude/opencode]` 把 diff 交给 agent 解释；附 skill 文件（`npx -y skills add remorses/critique`）；`critique hunks add` 提供稳定 hunk ID 的选择性暂存——「给人看的评审工具 + 给 agent 的接口」混合体。

**critique-review**（0 star 但结构典型）：`critique-review/SKILL.md` + `agents/openai.yaml` + `references/review-rubric.md`（仅涉及安全/数据完整性/并发/迁移时按需加载——渐进式上下文）。工作流：看 diff → 分类风险 → 读周边代码 → 用测试/搜索验证论断 → 先发 findings 再写 summary；严重度 P0–P3；输入覆盖 PR、本地 diff、commit、patch。`npx skills add` 安装，面向任意可加载 Markdown skill 的 agent。

### 3.3 商业产品（模式参考）

- **CodeRabbit**（闭源 SaaS，Pro $24/月/user）：GitHub/GitLab/Azure DevOps App + CLI（`coderabbit review`，`--prompt-only` 可接 Claude Code/Cursor 作 pre-commit 质量门）+ IDE 插件。PR 自动评审 + `@coderabbitai` 评论命令。`.coderabbit.yaml`：`path_filters` 排除、按路径 review instructions、tone；另有 "learnings" 记忆机制
- **Greptile**（闭源，Pro $30/seat/月，开源免费）：索引整个代码库构建文件/函数依赖图，"agent swarm" 跨文件上下文评审。`greptile.json`（`strictness: 1-3`、`commentTypes`、子目录级联覆盖）+ `.greptile/`（`config.json` + 自然语言 `rules.md`）+ dashboard Custom Context。有官方 Claude Code 插件
- **共性警示**：PR 触发型工具的评审发生在 commit/push 之后，**成本已沉没**——不适合直接嵌入 SDD 本地循环，更适合做 CI 终闸

### 3.4 Claude Code 官方评审能力（最直接的范本）

仓库 [anthropics/claude-code](https://github.com/anthropics/claude-code)（★142,204）`plugins/` 下两个官方插件（镜像分发于 [anthropics/claude-plugins-official](https://github.com/anthropics/claude-plugins-official)，★33.8k）：

**`/code-review` 插件**（[command 源文件](https://raw.githubusercontent.com/anthropics/claude-code/blob/main/plugins/code-review/commands/code-review.md)，作者 Boris Cherny）：slash command 形态的多阶段编排脚本，frontmatter 精简（`description` + `allowed-tools` 白名单，只允许 `gh pr view/diff/comment`、`mcp__github_inline_comment__*` 等）。流程：

1. 派 **haiku** agent 预判是否需评审（跳过 closed/draft/trivial/已被评论过的 PR）
2. haiku 收集相关 CLAUDE.md 文件路径；sonnet 总结 PR 变更
3. **并行 4 个评审 agent**：sonnet ×2 查 CLAUDE.md 合规；Opus 只看 diff 找明显 bug；Opus 找引入代码的安全/逻辑问题
4. 每个 issue 再派**并行验证 subagent**（bug 用 Opus、违规用 sonnet）二次确认
5. 过滤未通过验证的 issue；`--comment` 时发 inline 评论

评审维度为**高信号过滤**：只标记「编译/解析失败、确定产生错误结果、可引用原文的 CLAUDE.md 违规」；明确不标风格、依赖特定输入的潜在问题、主观建议、lint 能抓的问题。**不跑测试**（明确 "do not run the linter to verify"）。注意 README（v1.0.0，描述 0-100 打分 + 阈值 80）与当前 command 源文件（验证 subagent 机制）存在版本漂移，引用以源文件为准。

**`pr-review-toolkit` 插件**（作者 Daisy）：6 个专职 subagent——`comment-analyzer`、`pr-test-analyzer`、`silent-failure-hunter`、`type-design-analyzer`、`code-reviewer`、`code-simplifier`。以 [code-reviewer.md](https://raw.githubusercontent.com/anthropics/claude-code/blob/main/plugins/pr-review-toolkit/agents/code-reviewer.md) 为例：frontmatter `name / description / model: opus / color`；**description 写得极长**，内含三段 `<example>` 教主 agent 何时 proactive 触发——官方 subagent 触发条件撰写范本。评审维度：CLAUDE.md 合规、bug 检测（逻辑错误/race condition/内存泄漏/安全）、代码质量（重复、错误处理、可访问性、测试覆盖）；默认范围 `git diff` unstaged 变更。输出：每 issue 0-100 打分，**只报 ≥80**，按 Critical(90-100)/Important(80-89) 分组，附 file:line 与修复建议。README 建议工作流：写码 → code-reviewer → silent-failure-hunter → pr-test-analyzer → comment-analyzer → code-simplifier → 提 PR。

**社区合集**：

- [wshobson/agents](https://github.com/wshobson/agents)（★38,975，多 harness 插件市场）：`plugins/comprehensive-review/agents/code-reviewer.md`（`model: opus`，description 以 "Use PROACTIVELY for code quality assurance" 收尾；正文覆盖 Trag/Bito/Codiga、SonarQube/CodeQL/Semgrep、OWASP Top 10、IaC 审查）；另有 `architect-review`、`security-auditor`、编排命令 `full-review`/`pr-enhance`；skill 形态 `code-review-excellence/SKILL.md`（知识型）；治理向 `review-agent-governance/`（Cedar 策略 + hooks）
- [VoltAgent/awesome-claude-code-subagents](https://github.com/VoltAgent/awesome-claude-code-subagents)（★24,505）：`categories/04-quality-security/code-reviewer.md`，frontmatter 含显式 `tools: Read, Write, Edit, Bash, Glob, Grep` 白名单 + `model: inherit`；硬性 checklist："Code coverage > 80% confirmed"、"Cyclomatic complexity < 10"、"Zero critical security issues"
- [obra/superpowers requesting-code-review](https://raw.githubusercontent.com/obra/superpowers/main/skills/requesting-code-review/SKILL.md)：见 §4.2

### 3.5 大厂开源专项：alibaba/open-code-review（OCR）

仓库 [alibaba/open-code-review](https://github.com/alibaba/open-code-review)（★21,044，fork 1,526，Apache-2.0，2026-08 仍活跃开发；npm `@alibaba-group/open-code-review`，Go 1.25 预编译二进制按平台经 optionalDependencies 分发，CLI 名 `ocr`）。本节基于本地克隆源码级调研（文件路径均为仓库内相对路径）。

**背景与定位**：阿里集团内部官方 AI Code Review 助手，内部运行约两年（"服务数万开发者、发现数百万代码缺陷"），验证后开源。核心设计哲学是**「确定性工程 × Agent 混合」**（README.md:75-93）：文件选择、文件打包、规则匹配、评论定位与反思等"不能出错"的环节由工程逻辑硬约束，agent 只负责动态决策与上下文检索。README 明确指出纯语言驱动的 skill 式评审有三大痛点：**覆盖不全、位置漂移、质量不稳定**——这是对本报告 §4 中纯 prompt 驱动流派（superpowers/cc-sdd）的直接工程回应。

**Benchmark**：自建 benchmark（50 个开源仓库、200 个真实 PR、10 种语言、80+ 资深工程师标注 1,505 条 ground-truth）。关键数据（`pages/src/components/BenchmarkSection.tsx`）：同底模（Claude-4.6-Opus）下 OCR Precision 33.9% vs 裸 Claude Code 7.23%，token 消耗约 1/9~1/15，Recall 更低是**有意的 precision 优先取舍**。⚠️ 注意：仓库内 `docs/src/appendix/benchmark.md` 自录了 HN 第三方复测争议（复测 precision/recall 数字与官方有出入，官方承认早期版本 tool call 异常），引用数字需带此限定。

**架构**：

- CLI（Cobra）：`review`（workspace / `--from --to` 分支区间 / `--commit` / `--resume` 断点续审 / `--preview` 干跑）、`scan`（无 diff 的全文件扫描，审陌生代码库）、`delegate`（委派模式，见下）、`config`、`rules check`、`session list`、`viewer`（浏览器回放 session）
- 核心循环 `internal/llmloop/loop.go`：跨文件 LLM 工具调用执行器，含上下文压缩与异步工作池；`internal/agent/agent.go` 六步流水线：解析 diff → 注入 cross-file diff map → 冻结工具注册表 → 三层文件过滤 → 每文件并发子任务（默认 8）→ session 收尾；另有 token 预算 gate 与超大 diff 预过滤
- LLM 抽象 `internal/llm/providers.go`：三种协议（anthropic / openai / openai-responses），内置 **17 个 provider**（Anthropic、OpenAI、DashScope、火山、DeepSeek、Kimi、Z.AI、MiniMax、Ollama Cloud、LiteLLM 网关等），支持自定义

**评审机制**：

- 工具集刻意精简到 **6 个**（`internal/config/toolsconfig/tools.json`），"蒸馏自生产环境大规模工具调用 trace 分析"：`code_comment`（用 `existing_code` 滑动窗口匹配定位行号）、`file_read`、`file_read_diff`、`code_search`、`file_find`、`task_done`；另支持 MCP server 扩展
- **五阶段 prompt pipeline**（`internal/config/template/task_template.json`）：PLAN_TASK（diff>50 行先产出结构化风险分析 JSON）→ MAIN_TASK（主评审循环，最多 30 次工具调用）→ **RE_LOCATION_TASK**（独立重定位模块，治"位置漂移"）→ **REVIEW_FILTER_TASK**（独立反思过滤模块——只凭 diff 过滤"可确认为错误"的评论，存疑放行，precision 优先的关键闸门）→ MEMORY_COMPRESSION_TASK
- 输出结构化 JSON（`internal/model/review.go`）：行级区间、`suggestion_code`、`category`（bug/security/performance/maintainability/test/style/documentation/other）、`severity`（critical/high/medium/low）；`--format json` 供 CI 消费；`--audience agent` 抑制 UI 只输出摘要
- 评审维度组织**不是自然语言 skill，而是规则数据**：`internal/config/rules/system_rules.json` 把 glob（如 `**/*.java`、`.github/workflows/**`）映射到 33 个语言/文件类型的 Markdown checklist；用户规则四层优先级：`--rule` flag > `<repo>/.opencodereview/rule.json` > `~/.opencodereview/rule.json` > 内置；`merge_system_rule` 控制合并或替换

**与 SDD 结合的直接接口**：`--background` / `--background-file`（Markdown，8000 字符上限）把业务背景注入 prompt 的 `{{requirement_background}}` 占位符（PLAN 和 MAIN 两阶段，`internal/config/template/prompts/main_task_user.md:15-16`）——SDD 工作流可把 `spec.md`/`tasks.md` 在评审时经此喂给 reviewer，让"是否实现了 spec"成为一阶评审维度。

**接入形态**：GitHub composite Action（`action.yml`：**checkout 可信 base 分支而非 PR head 防 fork 投毒**；评论策略 = sticky summary 原地更新 + incremental 按 path+行区间 IoU≥0.6 去重 + severity/category 路由，低严重度降级到摘要、fail-open 不丢 finding）；AI agent 集成四形态——Claude Code marketplace 插件（`/open-code-review:review`、`/open-code-review:delegate-review`）、Codex 插件、Cursor 插件、OpenCode 原生工具；**通用 skill `skills/open-code-review/SKILL.md`** 是教宿主 agent 调 `ocr` CLI 的操作手册；**`open-code-review-delegate` 委派模式**：OCR 只做文件选择和规则解析（`ocr delegate preview/rule`），评审本身由宿主 agent 自己的 LLM 完成——**"工程管线"与"模型"解耦**，同一套管线同时服务独立 CLI 与嵌入现有 agent 两种形态。另有 VSCode 扩展（comment apply/discard/falsePositive）与 session 持久化 + Viewer 回放（评审记录可作可审计工件）。

**对 SDD+reviewer 项目的可借鉴点**：

1. `--background-file` 是现成的 spec 注入挂点，但目前只接受自由文本，不感知 SDD artifact 结构（delta spec、tasks 完成度）——见 §6.3
2. 确定性工程 × Agent 的边界划分：「哪些 spec 条目对应哪些文件」这类映射应工程化，而非让模型自由发挥
3. 独立的重定位 + 反思过滤后处理闸门，比 prompt 里叮嘱"别乱报"更有效
4. 规则即数据 + glob 匹配可平移为 per-artifact 规则（spec.md 用 spec 规则、代码用实现一致性规则）
5. Benchmark 驱动的 prompt 调优 + precision 优先 + CI 侧 severity 路由控噪
6. Delegate 模式：评审引擎做成"文件选择 + 规则解析"的确定性组件，模型判断留给宿主——与 §6.2 形态 B 的「薄 skill 层 + 宿主无关 CLI」思路完全同构

### 3.6 确定性静态分析层：codefuse-ai/CodeFuse-Query

仓库 [codefuse-ai/CodeFuse-Query](https://github.com/codefuse-ai/CodeFuse-Query)（★356，Apache-2.0；蚂蚁集团开源，ICSE 2025 论文配套）。注意活跃度：上游 GitHub 近一年基本停更（last push 2025-09），属「内部使用为主、核心交付物是 sparrow-cli release 二进制 + 论文」的项目。它不是 LLM 评审工具，而是**数据中心化静态分析系统**——对本调研的价值在于：它是「LLM reviewer 之下的确定性事实层」的现成实现，与 §3.5 OCR 的「确定性工程 × Agent」哲学同屬一脉。本节基于本地克隆源码级调研。

**架构三件套**：

- **COREF 数据模型**：`COREF = AST + ASG + CFG + PDG + Call Graph + Class Hierarchy + Documentation`，各语言 extractor 把源码归一化成关系型数据表。成熟度不均：Java/TS/JS/Go/XML 成熟（**只有 Java 额外有 ASG/Call Graph/Class Hierarchy/部分 CFG**），OC/C++/Python3/Swift/SQL/Properties 为 Beta，CFG/PDG 整体仍在建设
- **Gödel DSL**：Datalog 派生的声明式逻辑语言（编译到自修改版 Soufflé 执行）。选 Datalog 的理由：**单调性 + 终止性**——任何合法规则脚本必然终止（适合 CI 无人值守跑规则）、递归/传递闭包（调用链、继承链）是一等公民
- **平台化**：Sparrow CLI 两步走（`sparrow database create` 抽取 → `sparrow query run` 跑 `.gdl`，输出 json/csv/sqlite，**支持 `--sarif` 天然适配 CI 卡点与 GitHub code scanning**）；VSCode 插件；Query Center 在线服务（内部形态）

**变更影响分析（与本主题最相关，ICSE 2025 论文 Microscope）**：输入是 git diff 产物（两个 commit 间的变更文件 + 行号列表，由外部脚本注入 GDL 事实——仓库内 `gitdiff()` 是占位符，"diff → facts" 这步需自搭）；规则把变更行映射到 ECG 节点、过滤注释/日志/测试等非语义变更，再经数据依赖/调用依赖传递闭包做影响传播；**输出是受影响的对外接口列表**（RPC/HTTP 入口 + 完整调用链 + 数据库操作）。语言无关性来自 COREF 归一化——可跨 Java + MyBatis XML + Spring 注解 + TS 前端联合推理（motivation example：Java 新增字段 → RPC 接口返回类型 → BFF proxy 配置 → TS 前端调用点参数不匹配）。内部落地佐证：优酷精准测试体系（输入"文件+行号"，输出受影响方法/入口/调用链/DB 操作）。

**现成 GDL 脚本**（`example/`）：圈复杂度/扇入扇出/注释率度量、调用链、死代码检测（`UnusedMethod.gdl`）、`ChangeEffect.gdl`（变更函数 → 调用者传递闭包）、Spring/MyBatis/RPC 框架感知规则、`example/icse25/rules/` 全套 30+ 条变更影响规则。

**对 SDD+reviewer 项目的可借鉴点**（仓库自带 `codefuse-mdbook/src/llm/16-integration.md` 专门论证了与 LLM 的结合）：

1. **分层定位**："clangd 给你一个点看得准，CodeFuse-Query 给你整张图看得全"——LLM 评审的典型痛点「只见树木不见森林」（grep 局部、callers 深度受限、虚调用不准）正是 Datalog 传递闭包的强项。它属于**离线预计算的全局事实层**，与 LSP 的「在线、按需、局部精确」互补
2. **能给 reviewer 的事实**：全量调用链（不限 depth）；**变更波及范围**（diff → 受影响入口/接口/调用链——对 PR review 是直接输入：「这个 diff 会影响哪些对外接口」）；确定性缺陷规则预扫描；度量热区 → 评审优先级排序
3. **确定性分工**：monotonicity/termination 意味着结果可复现、必然终止——事实性结论交给 Datalog 做 CI 卡点，LLM 只做语义判断；`--sarif` 可直接接 GitHub Advanced Security / reviewdog
4. **接入成本需如实评估**：每语言要先跑 extractor 离线生成 COREF 数据（滞后于代码变更）；只有 Java 支持增量抽取；其 roadmap 给出的成败开关是**抽取覆盖率 >90% 才值得引入**。对 SDD 场景最实际的切入点是 **Java/TS/JS/Go 成熟语言 + 变更影响分析**这条线

---

## 4. 核心章节：评审嵌入 SDD 各阶段的模式

### 4.1 四个评审插入点（按缺陷修复成本递增排序）

```
spec/plan 评审 ──→ 任务级实现评审 ──→ pre-commit 门禁 ──→ PR/分支终审
（分钟级成本）      （任务刚完成）        （commit 前最后机会）   （成本已部分沉没）
```

**① Spec/Plan 评审（写码前）**：

- spec-kit `/speckit.analyze`（[模板原文](https://raw.githubusercontent.com/github/spec-kit/main/templates/commands/analyze.md)）：严格只读（"STRICTLY READ-ONLY"），必须在 tasks 之后、implement 之前运行，分析 spec/plan/tasks 三工件。六类检测通道：A. Duplication、B. Ambiguity（标记 "fast, scalable, secure" 等无可度量标准的模糊词）、C. Underspecification、D. Constitution Alignment、E. Coverage Gaps（"Requirements with zero associated tasks"）、F. Inconsistency。**Constitution 权威机制**：MUST 原则冲突自动定 CRITICAL，"require adjustment of the spec, plan, or tasks—not dilution"。严重度四级；报告含 Coverage Summary Table + Metrics；上限 50 条 findings。模板内置 **extension hooks**（`.specify/extensions.yml` 的 `hooks.before_analyze/after_analyze`，分 mandatory/optional）——「评审点可插拔」的官方机制。第三方扩展：[TEKIMAX/speckit-security](https://github.com/TEKIMAX/speckit-security) 在 implement 前加 STRIDE 威胁建模 gate
- [openkash/ai-agent-dev-workflow](https://github.com/openkash/ai-agent-dev-workflow) 的 `review-plan`：8 点计划评审，"Fixing a wrong abstraction in a plan costs minutes; in code, hours"
- [dlowd/claude-skill-critique](https://github.com/dlowd/claude-skill-critique)（15 star）：`/critique` 派生 1–2 个 "fresh-eyes critic agent" 对抗式评审计划/设计文档/代码，按严重度（Showstopper…）分级后 triage
- [Multi-Agent Spec Reviewer](https://mcpmarket.com/tools/skills/multi-agent-spec-reviewer)：Claude/GPT/Gemini 多模型并行审 spec，Completeness/Consistency/Feasibility/Clarity 四个 gate 评分

**② 任务级实现评审**：superpowers（§4.2）、cc-sdd `/kiro-impl`（§2.3）。

**③ Pre-commit 机械门禁**：imti.co（§4.3）、codex-review（§4.4）。

**④ PR/分支终审**：superpowers final code reviewer（最强模型 whole-branch）；CI 侧接 PR-Agent / claude-code-action / CodeRabbit 兜底。

被广泛引用的时序结论：**Stop hook 是"错误的触发点"**——`Stop` 触发时 commit 往往已发生，commit→push→review→fix-commit→push 循环成本已沉没；**`PreToolUse` 是时间线上唯一能廉价强制评审先于成本发生的位置**（[imti.co](https://imti.co/pre-commit-review-gate/)）。

### 4.2 标杆实现：obra/superpowers 的 subagent-driven-development

[SKILL.md 原文](https://raw.githubusercontent.com/obra/superpowers/main/skills/subagent-driven-development/SKILL.md)："Fresh subagent per task + task review (spec + quality) + broad final review"。

**时序**：Setup（worktree + ledger）→ 每任务：dispatch implementer subagent → 生成 review package（`scripts/review-package PLAN_FILE BASE HEAD`，**diff 以文件形式移交**，"Hand artifacts over as files"）→ 派 task reviewer 做 **spec 合规 + 代码质量双评审** → fix loop（最多 5 轮，1-3 轮 resume 原 implementer，4-5 轮换更强模型的 fresh implementer）→ 全部任务完成后派 **final code reviewer**（最强模型）做 whole-branch 评审 → 干净后进入 `finishing-a-development-branch` skill。

**关键纪律**（均可直接抄）：

- "Implementer self-review never replaces the task review; both are needed."
- "Never fix findings yourself in the controller session — controller fixes skip review."
- 评审者输入 = 三个文件路径（task brief、report、review package）+ 全局约束；"Never dispatch a task reviewer without a diff file"
- **熔断器**：第 5 轮后 controller 仲裁（adjudicate）剩余 findings，parked findings 必须带 ruling 记入 ledger，"a silent discard is forbidden"
- **ledger 机制**：`/.superpowers/sdd/<plan>/progress.md` 抗 context compaction——"Controllers without one have re-dispatched entire completed task sequences — the single most expensive failure observed"
- **模型分层**：机械任务用便宜模型，架构与终审用最强模型；"An omitted model inherits your session's model — often the most capable and most expensive — which silently defeats this section"；"Turn count beats token price"
- **no-subagents 契约**：implementer 不得自行派 reviewer——"every reviewer a worker spawned duplicated the task review the controller dispatched anyway — a full extra review seat per task"

配套 skill [requesting-code-review](https://raw.githubusercontent.com/obra/superpowers/main/skills/requesting-code-review/SKILL.md)：skill 自身不评审，而是**教协调者如何派发评审 subagent**——取 BASE/HEAD SHA，用 `general-purpose` subagent 填充模板 [code-reviewer.md](https://raw.githubusercontent.com/obra/superpowers/main/skills/requesting-code-review/code-reviewer.md)（占位符 `{DESCRIPTION}/{PLAN_OR_REQUIREMENTS}/{BASE_SHA}/{HEAD_SHA}`），"给精确构造的上下文，绝不给会话历史"。模板评审 5 维：Code Quality、Architecture、Testing（"Tests actually test logic (not mocks)?"、"All tests passing?"）、Requirements（对照 plan、无 scope creep）、Production Readiness。输出固定格式：Strengths / Issues(Critical-Must Fix / Important-Should Fix / Minor) / Recommendations / **Assessment: Ready to merge? Yes/No/With fixes**。强制触发点：每任务完成后、大特性完成后、合并 main 前（"Review early, review often"）。

### 4.3 Pre-commit 门禁标杆：imti.co 的 PreToolUse gate

[The Pre-Commit Review Gate](https://imti.co/pre-commit-review-gate/)（"AI on a Leash" 系列，博客文章而非打包项目，脚本需从文章复制）：

- `~/.claude/settings.json` 注册 `PreToolUse` hook（matcher: `Bash`），拦截 `git commit`
- **放行条件**：kill switch 文件、plan mode、diff < 20 行、纯文档改动
- 否则要求 `.claude/.last-review.md` 产物带与当前 diff **SHA-256 匹配**的 `reviewed_hash` 且 `verdict: CLEAN`
- 拦截时 deny reason 里**直接附带完整对抗性评审 prompt**，agent 下一轮无条件可执行
- 评审由 `general-purpose` 子代理完成，要求必填输出段（Findings / Suggestions / Paired-backend audit / Doc-vs-code walkthrough / Verdict）——"An agent can decline to think. It cannot silently decline to produce a section."
- **校准对抗 review theater**：findings 必须是 `file:line` 的具体缺陷；"could be cleaner" 类不计入；允许 dispute-in-writing（理由写进 commit body）与 defer-with-TODO；迭代上限 2 轮（例外 3 轮——仍有实质发现说明改动过大应拆分）。"A loop with no exit other than 'agent exhausts itself producing nits' is not a leash, it's a treadmill."
- **Fail-open 姿态**："A buggy gate that blocks legitimate work is worse than no gate, because you'll disable it permanently and never re-enable."
- 两个度量指标：post-commit review 发现漏网 bug 的频率（门太松）；平均每 PR 评审轮数 >2（门太紧）

### 4.4 跨模型评审：andreidavid/codex-review

[andreidavid/codex-review](https://github.com/andreidavid/codex-review)（小项目，~2 stars，机制有借鉴价值）：

- `PostToolUse` hook：Claude 经 Bash 成功 `git commit` 后，自动调用 **OpenAI Codex CLI** 评审该 commit；`[P1]`/`[P2]` findings 阻塞要求修复重提交；**Codex 错误与超时不阻塞**（"only findings do"）
- `Stop` hook 维持 fix/re-commit 循环，上限 `CODEX_REVIEW_MAX_LOOPS`（默认 5）；连续 FAIL 上限 `CODEX_REVIEW_MAX_ROUNDS`（默认 8），达上限 findings 降级 advisory
- 未 push 的 commit 用 `--amend` 折叠修复，"broken intermediate versions never survive in history"
- `/codex-review-plan`：对 `~/.claude/plans/` 的计划文件做写码前评审
- `/codex-review-waive`：豁免有争议 finding（按归一化标题匹配，行号变化仍生效）
- 状态全部存 `.git/` 内（按会话隔离并行 fix loop）
- 跨厂商评审动机见 [mindstudio.ai 分析](https://www.mindstudio.ai/blog/cross-vendor-ai-agent-review-claude-codex)

### 4.5 双评审互补：conformance vs correctness

[openkash/ai-agent-dev-workflow](https://github.com/openkash/ai-agent-dev-workflow)："Reviews are gates, not suggestions"。三个独立评审 agent 在隔离上下文运行："The reviewer didn't write the code... author-evaluator bias is cut by the setup"。时序：tracker 文件触发 `review-plan`（写码前）→ TDD 实现 → **`review-impl`**（conformance：代码是否符合计划）+ **`red-team`**（correctness：不管理计划、专挑 diff 的错；recall-biased 找候选再 verify 为 CONFIRMED/PLAUSIBLE）。设计论点："A bug that faithfully implements a flawed plan is caught only by `red-team`; a correct-but-off-spec change only by `review-impl`"。

### 4.6 双层验证栈：OpenHands verification stack

[官方博客 2026-06](https://www.openhands.dev/blog/20260506-the-verification-stack)，目前最完整的生产级双层设计：

- **Layer 1 Agent-Level Verifier（Critic Model）**：小快模型在 agent 工作过程中对轨迹打分，低分提前终止或重试，"在 push 前拦截明显失败的工作"
- **Layer 2 Repo-Level Verifier**：**code review agent**（skill 驱动，10 个按优先级排序的评审场景，前四项：数据结构分析 > 安全与正确性 > 测试缺口（拒绝 mock-only 测试）> 依赖/供应链风险）+ **QA agent**（真实运行软件：Understand→Setup→Exercise→Report，产出带命令/输出/截图证据的 QA 报告）
- 输出：行内评论 + 风险评估（🟢 Low / 🟡 Medium / 🔴 High）+ verdict；高风险 PR 标记给人类架构师，不自动合并
- **可定制机制**：仓库内放 `.agents/skills/custom-codereview-guide.md` 或 `AGENTS.md`，reviewer 从 **PR 分支**读取，改规则后 re-review 立即生效，形成持续改进循环
- 生产数据：在 `software-agent-sdk` 仓库运行 6 个月，1000+ 条评审覆盖 900+ PR，90% PR 使用自动评审，**平均合并时间下降 58%**，bot 评审 precision 接近人类水平

### 4.7 学术化表述：阶段级 grounding/validation hooks

[arXiv:2604.05278 "Spec Kit Agents"](https://arxiv.org/html/2604.05278v1)：把 Spec Kit 的 Specify/Plan/Tasks/Implement 每阶段前后加 **discovery hooks**（只读仓库探测，grounding）与 **validation hooks**（校验中间工件，如 "PLAN.md 引用的文件路径是否存在"；实现后跑测试/linters），plan-review 处留人工 checkpoint。128 次运行实验：context-grounding hooks 使 LLM-judge 质量分 3.51→3.66（+0.15，Wilcoxon p<0.05），测试兼容率 99.7–100%，SWE-bench Lite Pass@1 56.5%→58.2%；消融显示 Validation-only > Discovery-only，两者互补。

### 4.8 其他 multi-agent 流水线实现

- **BMAD quality gate**："A quality gate is a stage-transition checkpoint...that verifies each artifact meets defined criteria before the next agent begins work"；QA agent（Quinn, Test Architect）对 story 生成 PASS/CONCERNS/FAIL gate 文件（[reenbit 解析](https://reenbit.com/the-bmad-method-how-structured-ai-agents-turn-vibe-coding-into-production-ready-software/)）
- [KEYHAN-A/local-ai-agent-orchestrator](https://github.com/KEYHAN-A/local-ai-agent-orchestrator)：planner → coder → verifier → reviewer 四段流水线，LM Studio/OpenAI 兼容 API，SQLite 状态，per-plan Git 集成
- 并行评审：[hamy.xyz: 9 Parallel AI Agents That Review My Code](https://hamy.xyz/blog/2026-02_code-reviews-claude-subagents)（9 个子代理各审一个维度）
- Subagent 定义惯例：Claude Code 官方 `code-reviewer` 示例 description "Expert code reviewer. Use proactively after code changes."；第三方指南强调 "use proactively" 是自动触发关键短语（[shiplight.ai](https://www.shiplight.ai/blog/claude-code-subagents)）；opencode 用 `opencode.json` 定义 `"mode": "subagent"` + `"permission": {"edit": "deny"}` 做只读评审者（[opencode 文档](https://opencode.ai/docs/agents/)）

### 4.9 可复用设计模式（跨项目共性八条）

1. **评审者上下文隔离（author-evaluator 分离）**：reviewer 派生在 fresh context、不继承实现者会话历史，偏见"由架构消除而非靠 prompt 要求客观"
2. **工件即接口**：评审输入以**文件**移交（task brief、report、review package/diff），不粘贴进对话上下文
3. **机械强制 > 提示词自觉**：凡"必须每次都发生"的用 hook/gate 强制，凡"最好这样做"的放 CLAUDE.md/AGENTS.md（CLAUDE.md ~80% 遵守率 vs hooks 100%）
4. **双评审互补**：conformance（是否符合 spec/plan）与 correctness（diff 本身对不对、红队视角）分开
5. **评审产物持久化**：hash 绑定 diff 的 artifact（imti.co）、`.git/` 内状态与 JSONL 历史（codex-review）、ledger 文件（superpowers）——让状态在 context compaction 后存活，且阻止"review 完又改代码"的失效
6. **带出口的循环**：迭代上限（2/5/8 轮熔断）+ 仲裁机制（dispute-in-writing、defer-with-TODO、waive、parked-with-ruling），防无限 review 循环
7. **模型分层与成本意识**：评审用"与 diff 规模/风险相称的模型"，终审用最强模型；"Turn count beats token price"
8. **阶段级 grounding/validation hook**：把"评审"泛化为每个 phase 前后的只读探测与工件校验，在写码前捕获幻觉 API 与不存在的路径
9. **Planner–Generator–Evaluator 角色隔离**【v0.1 增补】（[Agent Patterns Catalog](https://www.agentpatternscatalog.org/patterns/planner-generator-evaluator-harness/)）：长时程工作拆成 Planner（产计划工件）/ Generator（每 chunk 新上下文）/ Evaluator（按固定 rubric 打分且看不到 Generator 轨迹），返回 pass/fail + 结构化 findings——固定 rubric 使评审行为跨 run 可复现；「工件即接口」（模式 2）同时也是可复现性的前提

### 4.10 门禁生命周期与 post-merge 学习：dsifry/metareview【v0.1 增补】

[dsifry/metareview](https://github.com/dsifry/metareview)（v0.6.0，README 快照见 [references/primary-sources/metareview](../../references/primary-sources/metareview/README.md)）："Local-first review gates and learning for specs, plans, code, epics, PRs, and post-merge follow-up"——与本项目定位几乎重合，且是 §6.2 形态 B 的活样本：

- **双宿主分发**：同一套门禁同时暴露为 Claude Code slash commands（`/setup` `/review-task-done` `/review-epic-ready` `/review-pr-ready` `/review-artifact` `/learn-post-merge` `/status`）与 Codex `$skills`（`$setup` 等）；本体是本地 CLI，编码 agent 把它当 completion gate 调用而非 CI webhook
- **四态生命周期**：`PASS` / `PASS_ADVISORY`（带非阻塞意见通过）/ `NEEDS_REVISION`（修复后带 `--previous-run <run-id>` 重跑同一 gate，跨 run 可追溯）/ `ESCALATED`（禁止同目标继续重试，人工必须收窄、拆分或重新设计目标）
- **五个必选对抗 lens**（以其 `rubrics/artifact-review-rubric.md` 为准）：Feasibility / Completeness / Scope & alignment / Architecture / Intent preservation——工件层视角，与 §4.5 的代码层 conformance/correctness 正交、可叠用；默认并行 subagent 执行，回退 in-session 自审时必须声明「本次评审非独立对抗」
- **`/learn-post-merge`**：合并后学习回喂后续评审——记忆飞轮在门禁层的先行者

---

## 5. 经验教训与常见坑（均有出处）

| 坑 | 说明 | 来源 |
|---|---|---|
| 评审触发点太晚 | Stop hook / PR-open 时才评审，commit/push 成本已沉没；PreToolUse 是唯一廉价位置 | [imti.co](https://imti.co/pre-commit-review-gate/) |
| Vibe-check 失效 | checklist 写进 memory/CLAUDE.md，agent"读了、自称考虑了、实际没走流程"——"in-context discipline does not survive contact with the model's own confidence"；团队级同现象："The rules are loaded into my context every session... I just don't follow them" | [imti.co](https://imti.co/pre-commit-review-gate/)、[augmentcode](https://www.augmentcode.com/guides/claude-code-spec-driven-development) |
| Review theater | prompt 要求"找出所有问题、不许 defer"→ 子代理学会编造 findings 显得尽职，30 分钟的改动收敛到 5 轮 2 小时；信号：平均每 PR 评审轮数 >2 | [imti.co](https://imti.co/pre-commit-review-gate/) |
| Context compaction 吞进度 | 无 ledger 的 controller 重复派发已完成任务——"the single most expensive failure observed" | superpowers SKILL.md |
| 重复评审席位 | worker 自行派 reviewer 与 controller 的 task review 重复——"a full extra review seat per task" | superpowers SKILL.md |
| 门禁自身 bug 阻塞工作 | 必须 fail-open，"A buggy gate that blocks legitimate work is worse than no gate" | imti.co；codex-review 同规（Codex 错误/超时不阻塞） |
| 琐碎改动被拖累 | 无 <20 行 / doc-only 豁免会 "train the agent to dismiss the gate as bureaucracy" | imti.co、[axonops/audit#464](https://github.com/axonops/audit/issues/464)（"The process relies on the AI remembering to run agents before each commit, which fails under cognitive load" → 改 pre-commit hook 机械强制） |
| 大 diff 结构性难审 | >800 行累计 diff 无论门禁多严都难审，"single biggest intervention is keeping changes small" | imti.co |
| 测试遮蔽（test masking） | agent 把失败测试改成 `pytest.skip()` 而非修代码；声明完成却未跑评审——要可检验的成功标准与 "show evidence" 而非 "assert success" | [augmentcode](https://www.augmentcode.com/guides/claude-code-spec-driven-development) |
| Hook 静默不触发 | 配置错误几乎无反馈，调试困难 | [stuartmason.co.uk](https://stuartmason.co.uk/posts/claude-code-hooks-not-working)、[ruflo issue #1084](https://github.com/ruvnet/ruflo/issues/1084) |
| spec 工件堆积成"work 的幻觉" | spec-kit 被批评生成大量文本、小特性开销过大；验证成本本身成为新瓶颈（METR 实验：开发者用 AI 反而慢 19%） | [spec-kit Discussion #1784](https://github.com/github/spec-kit/discussions/1784)、augmentcode |
| 角色化管线的 cargo cult | 角色 prompt 不产生独立专业能力，角色间传文本放大早期错误假设 | [vanja.io](https://vanja.io/265000-stars/) |

### 5.1 定量实证【v0.1 增补】：上表均为定性教训，此处补数据底座（详证见[补充卷 §1](landscape-supplement.md)）

| 实证 | 关键数字 | 设计含义 |
|---|---|---|
| AI 评审评论采纳率（16 个 Action / 178 仓库 / 22,326 条评论，[arXiv:2508.18771](https://arxiv.org/abs/2508.18771)） | 有效 AI 评论致改率 **0.9–19.2%** vs 人类 60%；hunk 级 6.5–19.2% vs 文件级 0.9–4.2% | finding 锚定 hunk/file:line 不是风格偏好，是 5–10 倍效果差 |
| 评论未解决归因（54,791 条 / 342 仓库，[arXiv:2607.21997](https://arxiv.org/abs/2607.21997)） | 头号原因 Intentional Design Decision（112 例）＞ Incorrect Suggestion（67 例） | 「spec 作为评审输入」（§6.3.1）的定量证明 |
| Beko 工业部署（ICSE 2025 SEIP，[arXiv:2412.18531](https://arxiv.org/abs/2412.18531)） | 73.8% 评论被处理；PR 关闭时间 5h52m→8h20m（p<0.001）；$0.48/PR | 评审非免费：gate 位置与豁免设计决定 cycle-time 代价 |
| CR-Bench 信噪比边界（[arXiv:2603.11078](https://arxiv.org/abs/2603.11078)） | 单轮 SNR 5.11（recall ~27%/precision ~3.6%）；Reflexion 后 recall ~33% 但 SNR 跌至 1.95 | 高阈值过滤方向正确；勿以加反思轮数换召回 |
| LLM-judge 一致率上限（Beko 2,604 条，[arXiv:2604.24525](https://arxiv.org/abs/2604.24525)） | 与人工标注一致仅 0.44–0.62；Likert 分级 > 二元判定 | 自动评分只做 triage 不做裁决；分级评分优于二元 |
| 同模型自偏好（[arXiv:2404.13076](https://arxiv.org/abs/2404.13076)） | 自偏好强度与自识别能力线性相关（Kendall tau 0.41→0.74） | fresh context 不消除模型自偏好 → 跨模型终审的定量依据 |

---

## 6. 设计建议：自建 SDD + Reviewer 工作流

### 6.1 与项目形态无关的通用骨架

```
explore → propose(spec+plan+tasks) → [plan review gate] → implement(每任务)
        → [task review gate: conformance + correctness] → [pre-commit hook gate]
        → verify(全量) → archive → [CI 终闸: PR 级评审]
```

直接可抄的组合拳：

1. **SDD 骨架抄 OpenSpec**：CLI（init/validate/archive）+ skills 注入 + `changes/` 目录 + delta specs；用 schema 依赖图把 review 做成一等 artifact（在 `tasks → implement` 之间加 `review` 节点）
2. **Reviewer 形态抄 superpowers**：skill 只负责「何时触发 + 如何派发」，真正评审用 fresh-context subagent；输入 = plan/spec 文件 + diff 文件（SHA 区间）；输出固定格式（Issues 分级 + Ready to merge? Yes/No）
3. **误报抑制抄官方 `/code-review`**：并行多维评审 → 验证 subagent 二次确认 → 高阈值过滤；明确不标风格/lint 能抓的问题
4. **强制执行用 hook**：PreToolUse 拦 commit + 评审工件 hash 绑定 diff；fail-open；琐碎改动豁免
5. **评审规则可演进抄 OpenHands**：规则文件放仓库内、随分支读取，改规则即改评审行为
6. **防跑偏三件套**：迭代上限熔断（如 5 轮）+ 仲裁机制（dispute-in-writing / defer-with-TODO / waive）+ ledger 持久化
7. **CI 侧终闸接现成工具**：PR 阶段用 PR-Agent（开源、`.pr_agent.toml` 可控、可输出 blocking check）兜底——本地 agent 评审 + PR 评审双层
8. **评审管线工程化抄 OCR**：文件选择/规则匹配/评论定位/反思过滤做成确定性代码，LLM 只做判断；spec 注入用 `--background-file` 式显式参数而非依赖模型自觉读文件；若想同时服务"独立 CLI"与"嵌入宿主 agent"两种形态，抄 OCR 的 delegate 模式（引擎只出文件清单+规则组，模型判断留给宿主）
9. **给 reviewer 喂确定性事实而非让它盲目 grep**（CodeFuse-Query 模式）：变更影响分析（diff → 受影响接口/调用链）、全量调用图、度量热区这类全局事实由静态分析离线预计算（Datalog/LSIF/CodeQL 均可），reviewer 的 prompt 里直接给结论；事实层用 SARIF 输出还可直接接 CI 卡点。注意接入成本：只有抽取覆盖率足够高的成熟语言值得引入

### 6.2 按项目形态的侧重

**形态 A：Claude Code 生态内（skill/plugin）**

- 分发：`SKILL.md` + `.claude/agents/*.md` subagent + `.claude/commands/*.md`，可走 plugin marketplace（参照 anthropics/claude-plugins-official）
- 门禁：`settings.json` 的 PreToolUse hook（matcher: Bash，拦截 git commit）
- 参照：superpowers（skill 编排）、官方 pr-review-toolkit（subagent description 写法范本）、imti.co（hook 门禁）
- 局限：绑定单宿主；hook 调试困难（静默不触发）

**形态 B：独立工具/框架（多 agent 宿主）**

- 分发：CLI（如 `npx your-tool init`）按宿主生成适配文件（参照 OpenSpec 支持 34 个工具的 `src/core/init.ts` + `WORKFLOW_TO_SKILL_DIR`）
- 评审引擎与宿主解耦：核心逻辑在 CLI（validate / review-package / diff-hash 校验），agent 侧只保留薄 skill 层
- CI 侧天然独立：直接提供 GitHub Action（参照 PR-Agent 的 Action/CLI/App 三形态、reviewdog 的管道模型）
- 参照：OpenSpec（多宿主注入机制）、PR-Agent、reviewdog

**形态 C：尚未确定（当前状态）**

- 建议先做形态 A 的 skill/plugin 原型（成本最低、迭代最快，superpowers 证明纯 Markdown 即可表达完整工作流），把评审引擎的确定性部分（diff 打包、hash 校验、门禁脚本）沉淀为与宿主无关的 shell/CLI 组件——这套组件日后可直接复用到形态 B

### 6.3 机会点（现有工具的空白）

1. **spec 作为评审输入**：高 star 评审工具几乎全部只看 diff + AGENTS.md；OCR 的 `--background-file` 提供了自由文本背景注入，但不感知 SDD artifact 结构；「对照 delta spec 做结构化 conformance 评审」已有先行者——superpowers/openkash 以 prompt 方式做了，[serpro69/claude-toolbox 的 review-spec skill](https://github.com/serpro69/claude-toolbox/blob/master/klaude-plugin/skills/review-spec/SKILL.md)（快照见 [references/primary-sources/review-spec](../../references/primary-sources/review-spec/SKILL.md)）给出双向六类机器可读 finding 码：`MISSING_IMPL / EXTRA_IMPL / SPEC_DEV / DOC_INCON / OUTDATED_DOC / AMBIGUOUS`（OUTDATED_DOC 是「spec 过时于代码」的反向通道），但均与 OpenSpec 式 SDD 骨架没有现成整合——差异化空间收窄为「delta-spec 结构感知 + 与机械门禁联动」。痛点定量佐证：54,791 条 agent 评审评论未解决的头号原因是缺设计意图（Intentional Design Decision 112 例 ＞ Incorrect Suggestion 67 例，[arXiv:2607.21997](https://arxiv.org/abs/2607.21997)，补充卷 §1.2）【v0.1 增补修订】
2. **评审门禁与 SDD artifact 状态机联动**：现有 hook 门禁只看 diff hash，不与 tasks.md 完成度、spec 校验结果联动；OpenSpec 的 schema 机制天然支持插入这种 gate，但官方 `/opsx:verify` 是建议性的而非强制的
3. **评审规则随分支演进**（OpenHands 模式）在开源 SDD 工具中尚无落地
4. **轻量化**：spec-kit 被批评「小特性开销过大」，带豁免机制、按改动规模自适应评审强度的实现有明确需求
5. **证据链评审**：OpenHands 的 QA agent（真实运行软件、带命令/输出/截图证据）在开源 skill 生态中无对应物

---

## 附录 A：主要信源清单

**SDD 框架**
- [Fission-AI/OpenSpec](https://github.com/Fission-AI/OpenSpec) · [OpenSpec 文档站](https://openspec.dev)（Commands / Concepts / CLI / Supported Tools / Migration Guide）
- [github/spec-kit](https://github.com/github/spec-kit) · [analyze.md 模板原文](https://raw.githubusercontent.com/github/spec-kit/main/templates/commands/analyze.md) · [GitHub Blog 官宣](https://github.blog/ai-and-ml/generative-ai/spec-driven-development-with-ai-get-started-with-a-new-open-source-toolkit/) · [Discussion #1784](https://github.com/github/spec-kit/discussions/1784) · [TEKIMAX/speckit-security](https://github.com/TEKIMAX/speckit-security)
- [obra/superpowers](https://github.com/obra/superpowers) · [subagent-driven-development SKILL.md](https://raw.githubusercontent.com/obra/superpowers/main/skills/subagent-driven-development/SKILL.md) · [requesting-code-review SKILL.md](https://raw.githubusercontent.com/obra/superpowers/main/skills/requesting-code-review/SKILL.md) · [code-reviewer.md 模板](https://raw.githubusercontent.com/obra/superpowers/main/skills/requesting-code-review/code-reviewer.md)
- [bmad-code-org/BMAD-METHOD](https://github.com/bmad-code-org/BMAD-METHOD) · [buildermethods/agent-os](https://github.com/buildermethods/agent-os) + [CodeMySpec v3 评测](https://codemyspec.com/blog/agent-os-review) · [gotalab/cc-sdd](https://github.com/gotalab/cc-sdd)
- [Kiro Specs 文档](https://kiro.dev/docs/specs/) · [Kiro Hooks 文档](https://kiro.dev/docs/hooks/) · [Tessl 发布博客](https://tessl.io/blog/tessl-launches-spec-driven-framework-and-registry/) · [Ry Walker: Tessl 调研](https://rywalker.com/research/tessl)
- 分析文章：[Martin Fowler 站 SDD 系列（Böckeler）](https://martinfowler.com/articles/exploring-gen-ai/sdd-3-tools.html) · [vanja.io: 265,000 Stars and I Don't Use Any of It](https://vanja.io/265000-stars/) · [nino-chavez/blueprint: 源码级 SDD 格局调研](https://github.com/nino-chavez/blueprint/blob/main/research/03-sdd-landscape-2026-06.md)

**评审工具**
- [alibaba/open-code-review](https://github.com/alibaba/open-code-review)（[官网](https://open-codereview.ai)；本节基于源码级调研，关键位置：`internal/llmloop/loop.go`、`internal/agent/agent.go`、`internal/config/rules/system_rules.json`、`internal/config/template/task_template.json`、`action.yml`、`skills/open-code-review/SKILL.md`）
- [codefuse-ai/CodeFuse-Query](https://github.com/codefuse-ai/CodeFuse-Query)（源码级调研，关键位置：`doc/2_introduction.md`、`example/icse25/`、`godel-script/README.md`、`codefuse-mdbook/src/llm/16-integration.md`；论文：[ICSE 2025 Microscope](https://conf.researchr.org/details/icse-2025/icse-2025-research-track/87/Datalog-Based-Language-Agnostic-Change-Impact-Analysis-for-Microservices)（[PDF](https://qingkaishi.github.io/public_pdfs/ICSE25.pdf)）、[arXiv:2401.01571](https://arxiv.org/abs/2401.01571)）
- [The-PR-Agent/pr-agent](https://github.com/The-PR-Agent/pr-agent) · [configuration.toml](https://raw.githubusercontent.com/The-PR-Agent/pr-agent/main/pr_agent/settings/configuration.toml)
- [reviewdog/reviewdog](https://github.com/reviewdog/reviewdog) · [danger/danger](https://github.com/danger/danger) · [danger/danger-js](https://github.com/danger/danger-js) · [anthropics/claude-code-action](https://github.com/anthropics/claude-code-action)（[solutions.md](https://raw.githubusercontent.com/anthropics/claude-code-action/main/docs/solutions.md)）
- [anthropics/claude-code plugins/code-review](https://github.com/anthropics/claude-code/blob/main/plugins/code-review/commands/code-review.md) · [pr-review-toolkit](https://github.com/anthropics/claude-code/tree/main/plugins/pr-review-toolkit) · [anthropics/claude-plugins-official](https://github.com/anthropics/claude-plugins-official)
- [Aider-AI/aider](https://github.com/Aider-AI/aider)（[lint/test 文档](https://aider.chat/docs/usage/lint-test.html)）· [kodustech/kodus-ai](https://github.com/kodustech/kodus-ai) · [remorses/critique](https://github.com/remorses/critique) · [repath500/critique-review](https://github.com/repath500/critique-review) · [dlowd/claude-skill-critique](https://github.com/dlowd/claude-skill-critique) · [sweepai/sweep](https://github.com/sweepai/sweep)（已停更）
- 商业参考：[CodeRabbit docs](https://docs.coderabbit.ai/) · [Greptile greptile.json 参考](https://www.greptile.com/docs/code-review/greptile-json-reference)

**评审模式与工程实践**
- [imti.co: The Pre-Commit Review Gate](https://imti.co/pre-commit-review-gate/) · [andreidavid/codex-review](https://github.com/andreidavid/codex-review) · [openkash/ai-agent-dev-workflow](https://github.com/openkash/ai-agent-dev-workflow) · [KEYHAN-A/local-ai-agent-orchestrator](https://github.com/KEYHAN-A/local-ai-agent-orchestrator)
- [OpenHands: The Verification Stack](https://www.openhands.dev/blog/20260506-the-verification-stack) · [arXiv:2604.05278 Spec Kit Agents](https://arxiv.org/html/2604.05278v1)
- [Claude Code sub-agents 官方文档](https://docs.anthropic.com/en/docs/claude-code/sub-agents) · [shiplight.ai: subagents 指南](https://www.shiplight.ai/blog/claude-code-subagents) · [opencode agents 文档](https://opencode.ai/docs/agents/)
- [augmentcode: Claude Code for SDD](https://www.augmentcode.com/guides/claude-code-spec-driven-development) · [axonops/audit#464](https://github.com/axonops/audit/issues/464) · [stuartmason: hooks 排错](https://stuartmason.co.uk/posts/claude-code-hooks-not-working) · [mindstudio.ai: 跨厂商评审](https://www.mindstudio.ai/blog/cross-vendor-ai-agent-review-claude-codex)
- [wshobson/agents](https://github.com/wshobson/agents) · [VoltAgent/awesome-claude-code-subagents](https://github.com/VoltAgent/awesome-claude-code-subagents) · [hamy.xyz: 9 Parallel AI Agents](https://hamy.xyz/blog/2026-02_code-reviews-claude-subagents) · [Multi-Agent Spec Reviewer](https://mcpmarket.com/tools/skills/multi-agent-spec-reviewer)

## 附录 B：存疑项与调研边界

1. **obra/superpowers ~275k stars** 由 GitHub API 两次调用确认（且两次调用间仍在增长），但数字异常高，正式对外引用前建议复核
2. OpenHands / PR-Agent / Sweep / Kodus / Mentat 的部分 star 数为 shields.io 缓存近似值（调研时 GitHub API 匿名限流 403 所致）；aider / OpenSpec / critique 等为 API 精确值
3. Kiro / Tessl / CodeRabbit / Greptile 为闭源产品，内部实现细节依赖官方文档与第三方实测，不可得源码验证
4. anthropics/claude-code 的 code-review README（v1.0.0，0-100 打分 + 阈值 80）与当前 command 源文件（验证 subagent 机制）存在版本漂移，引用以源文件为准
5. 官方无名为 `/review` 的命令，第三方文章中的 `/review` 多为自定义命令；官方市场仓库名为 `anthropics/claude-plugins-official`（非 "claude-code-plugins"）
6. cc-sdd 的 subagent 评审行为由 prompt 驱动，其实际可靠性无第三方基准验证
7. Cursor 侧未发现原生 review-gate hook 机制，主要为 Spec Kit 以 `.cursor/skills/` 安装使用的记录
8. imti.co 的 review-gate 是博客文章而非打包开源项目，脚本需从文章复制
9. 各项目 star 数增长极快，引用时请注意时效
10. OCR（alibaba/open-code-review）官方 benchmark 数据存在第三方复测争议（HN 复测 precision/recall 与官方数字有出入，官方承认早期版本 tool call 异常，见其 `docs/src/appendix/benchmark.md`）；引用其 benchmark 数字时应带此限定
11. CodeFuse-Query 上游 GitHub 近一年停更（last push 2025-09），且其"diff → facts"注入依赖外部脚本（仓库内 `gitdiff()` 为占位符），无现成 git diff 解析器；引入前需评估语言抽取覆盖率（其自身 roadmap 给出的阈值为 >90%）
12. 【v0.1 增补】「PR-Agent 每个工具都是单次 LLM 调用（~30 秒）」这一 README 表述已被其自身源码证伪（`pr_code_suggestions.py` 的 `/improve` 含一次强制 self-reflection 第二次调用，大 PR 还按 chunk 放大调用次数），引用其成本数据时勿用此说
13. 【v0.1 增补】检索中出现过「`openspec validate` 检查 spec-task 对齐（orphan task 检测）」的说法，与已知的格式/schema 校验语义有出入，疑为版本演进所致，未经本地实测前不并入正文
