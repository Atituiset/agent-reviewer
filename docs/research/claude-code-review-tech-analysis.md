# Claude Code 官方评审体系技术深度分析：claude-code-action 与 /code-review

> 日期：2026-08-28
> 目的：拆解 Anthropic 官方两条评审链路（GitHub Action 驱动的 PR 审核、本地 `/code-review` 命令）的技术实现，评估我们自建体系可借鉴的实现点
> 可信度标注：**[源码]** = 读到仓库源码/文档原文；**[官方]** = 官方文档声明但无源码；**[推测]** = 间接证据推断
> 调研底稿：本文件由子代理调研汇总整理，全部来源见附录

---

## 0. 全景：官方评审的三个形态

```
┌─────────────────────────────────────────────────────────────┐
│ 形态 A：托管服务 Code Review（GitHub App + Anthropic 云）      │
│   PR 触发 → 多 agent 并行 → 验证 → 去重排序 → inline 评论      │
│   $15-25/次，零运维，模型与数据全在 Anthropic                  │
├─────────────────────────────────────────────────────────────┤
│ 形态 B：claude-code-action（自托管 CI）                        │
│   自己的 runner + 自己的模型端点（可 DeepSeek）                │
│   tag 模式（@claude 交互）/ agent 模式（prompt 驱动自动评审）  │
├─────────────────────────────────────────────────────────────┤
│ 形态 C：本地 /code-review 命令（v2.1.x）                       │
│   effort 梯队 low→max + ultrareview 云端深度版                 │
│   finder angles 多路并行 → 三态验证 → ReportFindings 结构化    │
└─────────────────────────────────────────────────────────────┘
```

我们 CI 链路用的是形态 B 的 agent 模式；形态 C 的 prompt 工程是最值得拆解的部分；形态 A 是同一范式的云端放大版（内部细节未公开，多为 [推测]）。

## 1. claude-code-action 技术拆解（我们 CI 的执行底座）

### 1.1 分层与信任边界 [源码]

- **主 action**（`src/`）：GitHub 侧逻辑——模式检测、token、prompt 构建、MCP server 注入、评论管理
- **base-action**：薄封装，装 Bun + Claude Code，经 `@anthropic-ai/claude-agent-sdk` 的 `query()` 跑会话；**明确不做信任边界**——信任逻辑（actor 权限检查、从 base ref 恢复 `.claude/`/`CLAUDE.md` 配置防 PR 作者篡改）全在主 action

### 1.2 两种运行模式 [源码]

v1.0 后 `mode` 废弃，自动判定：

- **tag 模式**：@claude mention 触发。预取完整 GitHub 上下文（标题/body/全部评论/变更文件/图片），发追踪评论供模型反复编辑，可建分支提交代码
- **agent 模式**：有 `prompt` 输入即触发（自动评审的标准用法）。**只传 prompt 原文，不带任何 GitHub 上下文**——diff、场景路由全靠 prompt 模板注入（这正是我们 CI 的用法，也解释了为什么我们要自己打包输入）

### 1.3 Token 双链路 [源码]

- **默认**：OIDC（`id-token: write`）→ Anthropic 端点换 Claude GitHub App 安装 token；服务端校验 workflow 必须已合入默认分支；job 结束吊销
- **override**：`github_token` 输入直接跳过交换（我们用的路径，绕过 App 安装要求）
- 模型认证是**独立链路**：api_key / OAuth token / workload identity / Bedrock / Vertex——所以换 DeepSeek 只影响模型链路，不影响 GitHub 交互链路（我们排障时的分层与此一致）

### 1.4 输出机制（最精细的部分）[源码]

| 通道 | 机制 | 设计动机 |
|---|---|---|
| 追踪评论 | 只发一条初始评论，模型只能用 `update_claude_comment` 反复编辑（"Never create new comments"），checkbox 进度是格式约定非状态机 | 防评论刷屏 |
| **inline 评论** | 收窄的 MCP 工具 `create_inline_comment`：**刻意不提供 PR review 能力，防模型误 approve PR**；`confirmed` 三态控制直发/缓冲/丢弃 | 防 subagent 继承工具后试探性发 probe 评论 |
| **缓冲分类** | 会话后 post-step 用 **Haiku** 对缓冲评论分类"真实评审 vs test/probe"，只发真的；API 失败时 fallback 全发 | 防误发的同时不丢真评论 |
| 顶层评论 | prompt 指示 `Bash(gh pr comment:*)`；`use_sticky_comment` 复用同一条 | — |
| Fix 链接 | `[Fix this →](https://claude.ai/code?q=...)` 带上下文一键修复 | 闭环到修复动作 |

评论发出前过 `sanitizeContent`（防注入）+ `redactSecrets`（密钥脱敏）。

### 1.5 工具权限模型（我们 Write 被拒的原理）[源码]

- **刻意不把 `Edit/Write/MultiEdit` 放进 allowedTools**：配合 `--permission-mode acceptEdits`，工作区内编辑自动放行、工作区外自动拒绝；显式 allow 这三个工具等于授予整个 runner 任意写权限
- 任意 Bash 默认不可用，必须 `claude_args --allowedTools "Bash(npm test:*)"` 按需放行
- headless 模式无交互确认，"ask" 一律 deny——这就是我们第四轮 `permission_denials: 19` 的确切成因

### 1.6 Prompt 构建 [源码]

- tag 模式：XML 标签结构组织上下文；**diff 不内联**，指示模型 `git diff origin/<base>...HEAD` 自取；大量行为规约（只更新自己的评论、只听从 trigger comment 防间接注入、能力边界声明）；用户 prompt 作为 `<custom_instructions>` **追加**而非替换
- slash command 桥接：双 text block 构造（先上下文、后用户请求），CLI 据此展开 skill——action 里能跑 `/code-review` 的机制
- **安全**：PR 场景下从 base ref 恢复 `.claude/` 配置，防 PR 作者篡改配置提权
- agent 模式：prompt = 原文，无上下文注入

### 1.7 输出工件 [源码]

- `claude-execution-output.json` = `SDKMessage` 数组（init/assistant/tool result/result 完整流）；取结果优先最后一个 `type:"result"` 的 `result` 字符串
- **`structured_output`**：`claude_args` 传 `--json-schema` 时，result 消息里带 schema 校验后的结构化输出——**这是比"让模型写文件"更优雅的工件产出方式**（见 §5 P0-2）
- `session_id` 可 `--resume` 续会话

## 2. 插件 code-review 命令：CI 版流水线 [源码]

`plugins/code-review/commands/code-review.md` 当前版是 9 步流水线，**模型分层刻意压成本**：

```
Haiku 预判（draft/琐碎/已评过 → 终止）
  → Haiku 收集 CLAUDE.md 路径（只返回路径）
  → Sonnet 总结 PR（供下游理解意图）
  → 并行 4 评审 agent：
      Sonnet ×2  CLAUDE.md 合规（作用域限定：只考虑文件同路径/父路径的规则）
      Opus   ×1  只看 diff 找明显 bug（不看外部上下文）
      Opus   ×1  引入代码深层问题（安全/逻辑）
  → 逐 issue 验证 subagent（bug 用 Opus、违规用 Sonnet）
  → 过滤未通过者 → inline 评论（confirmed:true，一条 issue 只发一条）
```

关键纪律（与我们场景库「显式不报」清单高度同构）：

- "If you are not certain an issue is real, do not flag it. **False positives erode trust.**"
- 显式不报：pre-existing、看着像 bug 实际正确的、学究 nit、linter 能抓的（且**禁止真的去跑 linter 验证**）、已被 lint ignore 注释豁免的规则
- 每个 subagent 都带 PR 标题/描述理解作者意图
- 工具面纯只读（只有 `gh` 只读子命令 + inline 评论工具）

注意 [文档漂移]：同目录 README 还是旧版（0-100 打分制），以命令源文件为准。

## 3. 内置 /code-review skill：prompt 工程的集大成者 [源码：Piebald-AI 逆向提取 v2.1.247]

这是本次调研含金量最高的部分。内置 skill 已演进为**模板拼装架构**（变量插值组装各 effort 的 prompt）。

### 3.1 effort 梯队：成本-覆盖的工程化分档

| 级别 | 流程 | finder angles | verify | 上限 |
|---|---|---|---|---|
| low | 2 turns 单遍，不读全文件、不起 subagent、**不验证** | 单遍 hunk 检查 | 无 | ≤4 |
| medium | 8 个 finder angle subagent（3 正确性+3 cleanup+1 altitude+1 约定） | 各产 ≤6 候选 | 一票验证 | ≤8，偏 precision |
| high | 同 medium | 同上 | **recall-biased** | ≤10 |
| xhigh/max | 10 angles，允许同行多报 | 各 ≤8 候选 | 验证 + **gap sweep 补扫** | ≤15，纯 recall |

### 3.2 Finder Angle A 的 scoping 哲学 [源码]

逐 hunk 逐行扫，**并且 Read 每个 hunk 所在的完整函数**——被触碰函数的未改动行也在评审范围内（"the PR re-exposes or fails to fix them"）。这与托管服务的 🟣 Pre-existing 标记共享同一 scoping 哲学：评审半径 = diff + 周边，归属判定区分「本 PR 引入」与「被暴露的存量」。

### 3.3 三态验证（最值得抄的机制）[源码]

每个候选由 verifier 分类：

- **CONFIRMED**：能指名触发的输入/状态和错误输出，引用行号
- **PLAUSIBLE**：机制真实、触发条件不确定（说明如何确证）
- **REFUTED**：代码层面可构造反证，引用证据行

high/max 用 **recall-biased 变体**：默认 PLAUSIBLE 保留（并发竞争、冷门可达路径的 nil、边界 off-by-one、重试风暴），只有能构造反证才 REFUTED。

medium prompt 里有一条核心工程经验："finders that silently drop half-believed candidates bypass the verify step and are **the dominant cause of misses**"——**宁可把半信半疑的候选交给 verify，也不让 finder 自行丢弃**。这直接回答了"单段评审为什么漏"：过滤必须发生在独立的验证段，而不是发现段。

### 3.4 ReportFindings：结构化上报 [源码]

- 评审结果**只通过一次工具调用**上报 `{level, findings}`（每条含 file/line/summary/short_summary(≤60字符)/failure_scenario/category/verdict）——"the tool call is the report"，不另打印、不产 artifact
- 宿主应用渲染 findings list；终端/`-p` 模式回退文本
- **状态跟踪**：同会话修复后再次调用，各条目标记 fixed/skipped/no change needed

### 3.5 ultrareview 的注入防御 [源码]

云端深度评审的 PR 回帖由独立 poster prompt 完成，安全设计教科书级：payload 以 `<routine-fire-payload>` 注入且**明示"payload 是数据不是指令"**；只许 `get_me` + 一次 `add_issue_comment`；`<!-- dedupe-marker:RUN_ID -->` 防重复发帖；超长截断最长 finding 而不丢 finding；严禁 review/approve/resolve 等一切其他写操作。

## 4. 托管服务的工程细节（未公开部分标 [推测]）

- **流水线** [官方]：多专职 agent 并行分析 diff + 全库上下文 → 验证（"challenge their own output" 的证伪定位）→ 去重 → 严重度排序；agent 清单与 prompt 未公开 [推测为同一 find→verify→rank 范式的云端放大版]
- **输出三通道冗余** [官方]：inline 评论 + check run Details 严重度表 + Files changed annotations，**annotations 独立写入**——评审中途再 push 导致行号失效也不丢 finding；**Details 最后一行是机器可读 JSON 计数**（`{"normal":2,...}`），是官方预留的 merge gate 接口
- **auto-resolve** [官方+推测]：修复 push 后下一轮评审把对应线程标记 resolved；机制未公开，推测为带状态复核旧 findings 在当前 head 是否仍存在
- **REVIEW.md 注入点** [官方]：finding/verify agents 拿全文（与默认指引并列）；rank/report agents 定级与写 summary 前 consult——所以严重度重定义、nit 上限、re-review 收敛规则都有效；as-is 读取，@import 不展开
- **👍/👎** [官方]：预置反应按钮，merge 后收集计数调优 reviewer；运营核心信号是"修复即采纳"（auto-resolve 数）
- **效果数据** [官方 dogfood]：实质评审覆盖 PR 占比 16%→54%；工程师标记 <1% findings 为错误；>1000 行 PR 84% 有 findings（平均 7.5 个）；平均 20 分钟

## 5. 对我们的借鉴清单（按优先级）

### 5.1 方向验证（我们已与官方同构，无需改）

并行多维评审 → 验证段过滤、reviewer 纯只读、置信度阈值、"明确不报"清单、防 approve 的收窄工具面、按路径限定规则作用域（我们的 glob 路由 ≈ 他们的 CLAUDE.md 目录链作用域）。**我们的场景库 + SKILL 路由在规则组织上比单个 REVIEW.md 更结构化**（官方自己也承认 REVIEW.md as-is 读取、无路由）。

### 5.2 P0：直接可抄，成本极低

| # | 借鉴点 | 落到我们哪里 |
|---|---|---|
| P0-1 | **三态验证（CONFIRMED/PLAUSIBLE/REFUTED）替代二元置信度**；recall-biased 变体用于高严重度场景；"finders 不得自行丢弃半信候选"写进纪律 | `templates/reviewer-prompt.md` + 工件 schema 加 `verification` 字段 |
| P0-2 | **用 `structured_output`（`claude_args --json-schema`）产出工件**，替代"让模型 Write 文件"——正是我们被 Write 权限坑过的点，官方通道天然绕开 | CI 可复用 workflow 的评审步骤 |
| P0-3 | **机器可读计数行做 merge gate**（`{"normal":2,...}` 模式）：check run Details 末行附 JSON，需要 hard gate 的仓自行解析 | SARIF 步骤后加一行计数输出 |
| P0-4 | **effort 分档**：按 PR 规模选 low/medium/high（小 PR 单遍不起 subagent，大 PR 才上多 angle） | CI gate 步骤按 diff 行数分档 |
| P0-5 | **buffered inline + 会话后 Haiku 分类**：如果我们启用 inline 评论，直接用 action 内置机制（`confirmed` 省略进缓冲，post-step 自动分类）——不需要自建 | 未来 inline 评论功能 |

### 5.3 P1：值得做，中等成本

| # | 借鉴点 | 说明 |
|---|---|---|
| P1-1 | **两个新场景**：silent-failure-hunter（静默失败猎手：空 catch/只 log 不处理/静默跳过）与 pr-test-analyzer（行为覆盖分析 + criticality 打分）——我们场景库目前没有这两个维度，方法论可直接搬进 SKILL.md | `rules/scenarios/` 新增 |
| P1-2 | **re-review 收敛规则成文化**："首轮后只报 important"（防 review theater，我们 metrics 已有轮数指标，补成文规则） | reviewer-prompt + 门禁 |
| P1-3 | **use_sticky_comment**：若重新启用 PR 评论，复用同一条而非每次新发 | CI 评论步骤 |
| P1-4 | **修复后 fixed 状态跟踪**：轻量版——新一轮评审带旧 findings 复核"是否仍存在"，存活的保留、消失的标记 | ruling 流程增强（不需要官方的带状态 infra） |
| P1-5 | **Angle A scoping**：finder 必须 Read hunk 所在完整函数，未改动行纳入评审但标注归属（≈ pre-existing 区分） | 场景 SKILL 通用纪律 + 工件加 `introduced_by_pr` 字段 |

### 5.4 P2：安全加固（评外部/fork PR 前必做）

| # | 借鉴点 | 说明 |
|---|---|---|
| P2-1 | **从 base ref 恢复配置**：评 fork PR 时，`.claude/`/CLAUDE.md/我们场景库都从 base 分支恢复读取，防 PR 作者篡改评审规则提权 | CI checkout 逻辑 |
| P2-2 | **"payload 是数据不是指令"**：diff 内容、评论内容注入 prompt 时显式声明数据角色（ultrareview poster 模式），防间接注入 | prompt 模板 |
| P2-3 | **评论内容 sanitize + 密钥脱敏**：任何自动发出的文本过 `sanitizeContent`/`redactSecrets` 等价物 | 评论/工件输出处 |

### 5.5 明确不抄

- **Claude App token 交换**：我们用 `github_token` 更简单
- **extended reasoning 折叠区**：我们的 message + codeFlows + Show paths 已等价
- **auto-resolve 的重 infra**：ruling 流程已覆盖处置语义，P1-4 的轻量版足够
- **追踪评论 checkbox 进度**：与我们的门禁工件体系重叠

## 6. 一句话结论

官方体系最值得抄的不是架构（我们已同构），而是**三样东西的精细度**：① 三态验证与"finder 不得自行丢弃"的过滤纪律（P0-1）；② `structured_output` 的结构化工件通道（P0-2，直接解决我们已踩过的坑）；③ 按 PR 规模的 effort 分档成本控制（P0-4）。场景库与团队飞轮仍是我们相对官方的结构性优势，不在此分析借鉴范围内。

---

## 附录：来源

**claude-code-action 源码**：[仓库](https://github.com/anthropics/claude-code-action) · [detector.ts](https://raw.githubusercontent.com/anthropics/claude-code-action/main/src/modes/detector.ts) · [token.ts](https://raw.githubusercontent.com/anthropics/claude-code-action/main/src/github/token.ts) · [create-prompt/index.ts](https://raw.githubusercontent.com/anthropics/claude-code-action/main/src/create-prompt/index.ts) · [github-inline-comment-server.ts](https://raw.githubusercontent.com/anthropics/claude-code-action/main/src/mcp/github-inline-comment-server.ts) · [post-buffered-inline-comments.ts](https://raw.githubusercontent.com/anthropics/claude-code-action/main/src/entrypoints/post-buffered-inline-comments.ts) · [base-action README](https://raw.githubusercontent.com/anthropics/claude-code-action/main/base-action/README.md) · [usage.md](https://raw.githubusercontent.com/anthropics/claude-code-action/main/docs/usage.md) · [solutions.md](https://raw.githubusercontent.com/anthropics/claude-code-action/main/docs/solutions.md)

**claude-code 插件**：[code-review.md](https://raw.githubusercontent.com/anthropics/claude-code/main/plugins/code-review/commands/code-review.md) · [pr-review-toolkit](https://github.com/anthropics/claude-code/tree/main/plugins/pr-review-toolkit)（6 个 agent 原文）

**内置 skill 逆向**：[Piebald-AI/claude-code-system-prompts](https://github.com/Piebald-AI/claude-code-system-prompts)（v2.1.247 npm 包提取；含 [effort 各档](https://raw.githubusercontent.com/Piebald-AI/claude-code-system-prompts/main/system-prompts/agent-prompt-code-review-part-7-high-effort-mode.md)、[三态验证](https://raw.githubusercontent.com/Piebald-AI/claude-code-system-prompts/main/system-prompts/agent-prompt-code-review-part-4-three-state-verification-phase.md)、[recall-biased 变体](https://raw.githubusercontent.com/Piebald-AI/claude-code-system-prompts/main/system-prompts/agent-prompt-code-review-part-5-recall-biased-verification-phase.md)、[ReportFindings](https://raw.githubusercontent.com/Piebald-AI/claude-code-system-prompts/main/system-prompts/agent-prompt-code-review-part-10-reportfindings-output-format.md)、[ultrareview poster](https://raw.githubusercontent.com/Piebald-AI/claude-code-system-prompts/main/system-prompts/agent-prompt-ultrareview-github-comment-poster.md)）——属第三方逆向，引用时注意其非官方身份

**托管服务**：[官方文档](https://code.claude.com/docs/en/code-review) · [CodeAnt 分析](https://codeant.ai/blogs/anthropic-claude-code-review) · [tessl 报道](https://tessl.io/blog/anthropic-launches-ai-code-review-agents-that-scan-pull-requests-for-bugs)

**未确证开放问题**：托管服务 agent 清单与 prompt、去重算法、auto-resolve 判定细节、👍/👎 消费方式、Angle A 以外各 finder angle 的完整文本。
