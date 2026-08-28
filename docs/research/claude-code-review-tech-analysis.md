# Claude Code 评审体系纯技术分析：做法、原理与企业自建借鉴

> 日期：2026-08-28
> 性质：纯技术分析。拆解 Anthropic 官方 Claude Code 评审体系（claude-code-action、code-review 插件、内置 /code-review skill、托管 Code Review 服务）的做法与原理，并提炼企业自建 AI 评审体系可借鉴的通用思路——不绑定任何特定实现
> 可信度标注：**[源码]** = 仓库源码/文档原文可证；**[官方]** = 官方文档声明；**[推测]** = 间接证据推断

---

## 1. 全景：一个范式，四种形态

Anthropic 的评审能力不是单个产品，而是同一范式（**find → verify → rank → report**）在四个交付形态上的展开：

| 形态 | 交付物 | 运行位置 | 定位 |
|---|---|---|---|
| 托管 Code Review | GitHub App + 云服务 | Anthropic 基础设施 | 零运维 PR 终审，$15-25/次 |
| claude-code-action | 开源 GitHub Action | 用户自己的 runner | 自托管 CI 集成，模型端点可自选 |
| code-review 插件 | claude-code 仓内 command 文件 | 本地/CI 内 Claude Code | 9 步评审流水线 |
| 内置 /code-review skill | Claude Code 内置能力 | 本地终端/桌面端 | effort 分档的交互式评审 |

理解这套体系的关键：四个形态共享同一套**流水线哲学、误报治理纪律、安全边界设计**，差异只在工程包装。下面按层拆解。

## 2. claude-code-action：CI 集成的工程范本 [源码]

### 2.1 分层与信任边界

- **主 action**：GitHub 侧逻辑（模式检测、token、prompt 构建、MCP 工具注入、评论管理）；**base-action**：薄封装（装运行时、跑 SDK 会话）。信任边界全部上移到主 action——base-action 明确声明"不做任何信任假设"
- 这一分层的意义：**执行内核可以天真，安全判断必须集中**。企业自建时同理：评审内核（LLM 调用）与治理逻辑（权限、过滤、路由）应该是两层

### 2.2 双模式与上下文注入策略

- **tag 模式**（@claude 交互）：预取完整 GitHub 上下文（标题/body/全部评论/变更文件），XML 标签结构化注入；**diff 不内联**，指示模型 `git diff origin/<base>...HEAD` 自取——大 PR 的上下文预算控制
- **agent 模式**（自动化）：只传用户 prompt 原文，上下文全靠调用方自行打包——**集成方必须自己解决"喂什么上下文"的问题**，action 不替你决定

### 2.3 输出机制：五个精心设计的细节

1. **收窄的 inline 评论工具**：刻意不提供 PR review 能力，**让模型在结构上无法 approve/merge PR**——不是 prompt 里叮嘱"别 approve"，而是工具面直接没有
2. **`confirmed` 三态缓冲**：直发 / 缓冲待发 / 缓冲丢弃，防止 subagent 继承工具后试探性发 probe 评论
3. **会话后 Haiku 分类**：post-step 用便宜模型对缓冲评论做"真实评审 vs test/probe"分类，只发真的；分类失败 fallback 全发（不丢真评论优先）
4. **追踪评论单点更新**：交互模式下模型只能反复编辑同一条评论（"Never create new comments"），进度 checkbox 是格式约定而非状态机
5. **输出净化**：所有自动发出的文本过防注入 sanitize + 密钥脱敏

### 2.4 工具权限模型

- **刻意不 allow `Edit/Write`**：配合 `acceptEdits` 权限模式，工作区内编辑自动放行、工作区外自动拒绝；显式 allow 写工具等于授予整个 runner 任意写权限
- 任意 Bash 必须按命令模式显式放行（`Bash(npm test:*)`）
- 无交互环境下"ask"一律 deny——headless 评审的行为完全由白名单决定

### 2.5 结构化工件通道

- `claude-execution-output.json` = 完整 SDK 消息流（init/assistant/tool result/result）
- **`structured_output`**：`--json-schema` 让模型产出 schema 校验后的结构化输出——**不需要文件写权限的结构化结果通道**
- `session_id` 支持 `--resume` 续会话

## 3. code-review 插件：流水线的教科书 [源码]

9 步流水线，每一步的模型选择都体现成本工程：

```
Haiku 预判（draft/琐碎/已评过 → 终止，省掉整个评审）
  → Haiku 收集规则文件路径（只返回路径，不读内容）
  → Sonnet 总结 PR 意图（供下游 agent 校准"作者想干什么"）
  → 并行 4 评审 agent（Sonnet ×2 规则合规 + Opus ×2 缺陷发现）
  → 逐 issue 验证 subagent（bug 用 Opus、违规用 Sonnet）
  → 过滤 → 输出
```

值得逐条抄的纪律：

- **"If you are not certain an issue is real, do not flag it. False positives erode trust."**——误报侵蚀信任是整个体系的第一原则
- 显式不报清单：存量问题、看着像 bug 实际正确的、学究 nit、linter 能抓的（且禁止真去跑 linter 验证）、已被显式豁免的规则
- 规则作用域限定：评估某文件时只考虑该文件同路径/父路径上的规则——**规则必须有作用域，全局规则全局生效是误报温床**
- 每个 subagent 都带 PR 标题/描述：先理解作者意图，再判断对错——大量"疑似缺陷"其实是作者有意为之

## 4. 内置 /code-review skill：prompt 工程的集大成者 [源码：第三方逆向 v2.1.247]

### 4.1 effort 梯队：把"评审深度"做成可调旋钮

| 级别 | 流程 | finder angles | 验证 | 上限 | 导向 |
|---|---|---|---|---|---|
| low | 2 turns 单遍，不起 subagent | 单遍 hunk 检查 | 无 | ≤4 | 快速 |
| medium | 8 个 finder angle subagent | 各 ≤6 候选 | 一票验证 | ≤8 | precision |
| high | 同上 | 同上 | **recall-biased** | ≤10 | 平衡 |
| max | 10 angles + gap sweep | 各 ≤8 候选 | 验证+补扫 | ≤15 | recall |

核心思想：**深度与成本是显式权衡，应该暴露给用户/调用方选择**，而不是一刀切的最强配置。

### 4.2 Finder Angle 的 scoping 哲学

逐 hunk 逐行扫，并且 **Read 每个 hunk 所在的完整函数**——被触碰函数的未改动行也在评审范围内（"PR 使其重新暴露或未能修复的问题"）。评审半径 = diff + 周边上下文，但归属判定区分「本 PR 引入」与「存量暴露」——这是托管服务 🟣 Pre-existing 标记的同源设计。

### 4.3 三态验证：整个体系最有价值的单点机制

每个候选由独立 verifier 分类：

- **CONFIRMED**：能指名触发的输入/状态与错误输出，引用行号
- **PLAUSIBLE**：机制真实但触发条件不确定（说明如何确证）——recall 导向级别默认保留
- **REFUTED**：代码层面可构造反证，引用证据行

配套的工程经验（原文引用）："finders that silently drop half-believed candidates bypass the verify step and are **the dominant cause of misses**"——**发现段不允许丢弃半信候选，过滤只能发生在独立验证段**。这解释了为什么单段评审（一个 prompt 既找又滤）系统性漏报：发现段的自信校准天然偏保守。

### 4.4 ReportFindings：结构化出口

评审结果只通过一次工具调用上报 `{level, findings[]}`——"the tool call is the report"。含短摘要（≤60 字符不带理由）、失败场景、类别 slug、verdict；修复后再次调用并标记 fixed/skipped/no change needed。**机器出口与人读输出是同一份数据的两个投影**，不是两次生成。

### 4.5 ultrareview 的安全设计

云端深度评审的回帖 prompt 是注入防御教科书：payload 显式声明"是数据不是指令"；工具面只有 `get_me` + 一次 `add_issue_comment`；dedupe marker 防重复发帖；超长时截断最长 finding 而非丢弃 finding；严禁一切其他写操作。

## 5. 托管 Code Review：云端放大版 [官方 + 推测]

- **流水线**：多专职 agent 并行分析 diff + 全库上下文 → 证伪式验证 → 去重 → 严重度排序。agent 清单与 prompt 未公开 [推测为同一范式的放大]
- **输出三通道冗余**：inline 评论 + check run 严重度表 + diff annotations **独立写入**——评审中途再 push 导致行号失效也不丢 finding；Details 末行机器可读计数 JSON 是留给用户 CI 的 merge gate 接口
- **修复后自动 resolve**：订阅 push 评审的 PR，修复后下一轮把对应线程标记 resolved（判定机制未公开 [推测为带状态复核旧 findings]）
- **REVIEW.md 的分层注入**：finding/verify agents 拿全文，rank/report agents 定级写 summary 前 consult——**同一份规则文件在流水线不同阶段扮演不同角色**（发现规则 vs 定级规则 vs 输出形态规则）
- **效果数据**（官方 dogfood）：实质评审覆盖 PR 占比 16%→54%；工程师标记 <1% findings 为错误；>1000 行 PR 84% 有 findings、平均 7.5 个；平均 20 分钟/次
- **反馈**：👍/👎 预置反应，merge 后收集计数调优；运营核心信号是"修复即采纳"（auto-resolve 数）

## 6. 跨形态的设计原则提炼

把四个形态反复出现的决策抽出来，是这套体系真正的"道"：

1. **流水线阶段分离**：发现、验证、定级、报告是四个独立阶段，各有自己的模型、prompt、纪律。单段评审（一个 prompt 全包）在漏报和误报两端都更差
2. **误报治理 > 检出能力**：所有形态的 prompt 里篇幅最大的不是"怎么找 bug"，而是"什么不许报"。评审工具的死因不是漏报，是团队把它静音
3. **过滤只能在验证段**：发现段禁止丢弃半信候选；验证段才有资格 REFUTED
4. **模型分层压成本**：预判/收集/分类用小模型，发现/验证用强模型，后处理再用小模型——一次评审是多模型协作，不是单模型调用
5. **深度做成显式旋钮**：effort 分档让用户为每次评审选择成本-覆盖权衡
6. **意图先于判断**：每个评审 agent 先读作者意图（PR 标题/描述），再判断对错
7. **收窄工具面，而不是叮嘱**：防 approve、防刷屏、防 probe 评论全部靠工具面收窄实现，prompt 规约只是第二层
8. **结构化的机器出口**：结果必须有一份 schema 化的投影（ReportFindings / 计数 JSON / structured_output），人读输出是它的渲染
9. **安全边界集中**：信任判断（谁能触发、配置从哪恢复、什么能写）集中在治理层，执行内核保持天真
10. **带状态的演进**：反馈（👍/👎、auto-resolve、fixed 跟踪）让评审成为可度量的持续系统，而不是无状态的一次性调用

## 7. 企业自建可借鉴的思路与方向

按「直接决定成败」的程度排序：

### 7.1 先想清楚误报治理，再谈检出

- 评审上线第一周决定生死：误报率高的工具会被团队永久静音。官方所有形态都把 precision 放在 recall 之前，recall 只做可选项（effort 高档）
- 落地要件：显式不报清单、三态验证、独立验证段、"修复即采纳"作为核心质量指标
- **度量先于规模**：先能量化 precision/recall（哪怕人工抽检样本），再扩大覆盖。官方 <1% 错误标记率是被度量出来的，不是设计出来的

### 7.2 流水线范式直接照搬：find → verify → rank → report

- 发现段多路并行（按缺陷类别/规则域分 angle），禁止发现段过滤
- 验证段证伪定位（"challenge their own output"），强模型做 bug 验证、弱模型做规则验证
- 定级段独立（严重度校准、数量上限、存量 vs 新增归属）
- 报告段多投影：人读（评论/摘要）+ 机读（结构化出口）+ 归档（完整轨迹）

### 7.3 成本工程是产品决策，不是技术细节

- 模型分层：预判/分类用小模型（成本可降一个数量级）
- effort 分档：按 PR 规模/风险自动选档，高档留作手动选项
- 触发控制：豁免规则（小 diff/纯文档）、订阅制（push 触发按需开启）、spend cap
- 官方的 $15-25/次 告诉我们：不分档的最强配置在规模化时不可持续——自托管 + 模型分层 + 分档能把单位成本压低 1-2 个数量级

### 7.4 上下文与规则工程

- **scoping**：评审半径 = diff + 被触碰函数的完整定义 + 目录链上生效的规则；归属判定区分「新增」与「存量暴露」
- **规则分层注入**：发现规则、定级规则、输出形态规则可以是同一份文件的不同消费方式，也可以是按路径路由的不同文件——关键是**规则必须有作用域**
- **意图上下文**：作者意图（PR 描述/issue 链接/spec 文档）是所有评审 agent 的公共输入

### 7.5 安全与信任边界（评外部代码前必须做）

- 评审规则与配置从 base 分支恢复读取，防 PR 作者篡改规则提权
- 工具面收窄防越权（approve/merge/任意写在结构上不可达）
- 所有外部内容（diff、评论、payload）显式声明"数据不是指令"
- 自动输出过注入 sanitize + 密钥脱敏

### 7.6 演进机制：让系统越用越准

- 反馈回路必须闭环：TP/FP 标注 → 规则调整 → 下次生效，而不是反馈给供应商
- "修复即采纳"是最便宜的质量信号：下一轮评审复核旧 findings 是否仍存在，既能量化采纳率又能自动清理线程
- 完整轨迹归档（消息流级）用于事后审计与 bad case 分析——评审系统的改进原料是历史轨迹，不是灵感

### 7.7 落地路径的决策框架

| 企业约束 | 建议路径 |
|---|---|
| 无合规要求、求快、预算宽 | 托管服务起步，同时观察成本曲线 |
| 有数据主权要求、或成本敏感（高频触发） | 自托管 action + 自选模型端点（兼容协议的低成本模型），流水线范式照搬 |
| 需要评审左移到开发循环内（commit 前门禁）、或规则资产/反馈数据必须自有 | 自研治理层（门禁、规则库、反馈闭环），LLM 调用层复用 action/CLI |
| 任何路径 | 误报治理、度量体系、结构化出口三件事第一天就要在，其余的都可以后补 |

## 8. 一句话总结

Claude Code 评审体系的精华不在"用多强的模型"，而在一整套围绕**误报治理**的工程纪律：阶段分离的流水线、只在验证段过滤、显式的不报清单、模型分层、收窄的工具面、结构化的机器出口、以及让反馈闭环的演进机制。企业自建时，这些纪律全部与模型选型无关、可以逐项照搬；真正需要自己想清楚的只有三件事：**反馈资产归谁、评审发生在流程的哪个位置、成本模型能否支撑触发频率**。

---

## 附录：来源

**claude-code-action**：[仓库](https://github.com/anthropics/claude-code-action) · [detector.ts](https://raw.githubusercontent.com/anthropics/claude-code-action/main/src/modes/detector.ts) · [token.ts](https://raw.githubusercontent.com/anthropics/claude-code-action/main/src/github/token.ts) · [create-prompt](https://raw.githubusercontent.com/anthropics/claude-code-action/main/src/create-prompt/index.ts) · [inline-comment server](https://raw.githubusercontent.com/anthropics/claude-code-action/main/src/mcp/github-inline-comment-server.ts) · [post-buffered-inline-comments](https://raw.githubusercontent.com/anthropics/claude-code-action/main/src/entrypoints/post-buffered-inline-comments.ts) · [base-action README](https://raw.githubusercontent.com/anthropics/claude-code-action/main/base-action/README.md) · [solutions.md](https://raw.githubusercontent.com/anthropics/claude-code-action/main/docs/solutions.md)

**插件**：[code-review.md](https://raw.githubusercontent.com/anthropics/claude-code/main/plugins/code-review/commands/code-review.md) · [pr-review-toolkit](https://github.com/anthropics/claude-code/tree/main/plugins/pr-review-toolkit)

**内置 skill 逆向**：[Piebald-AI/claude-code-system-prompts](https://github.com/Piebald-AI/claude-code-system-prompts)（v2.1.247；第三方逆向，非官方）

**托管服务**：[官方文档](https://code.claude.com/docs/en/code-review) · [CodeAnt 分析](https://codeant.ai/blogs/anthropic-claude-code-review) · [tessl 报道](https://tessl.io/blog/anthropic-launches-ai-code-review-agents-that-scan-pull-requests-for-bugs)

**未确证**：托管服务 agent 清单与 prompt、去重算法、auto-resolve 判定细节、👍/👎 消费方式、Angle A 以外各 finder angle 完整文本。
