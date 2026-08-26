# SKILL 建设思路与逻辑：三方案交叉分析

> 版本：v0.1 · 2026-08-26
> 定位：为 MVP `agents/task-reviewer.md` 与 `templates/reviewer-prompt.md` 的撰写提供设计依据（对应 [MVP 设计 §2.3](../../docs/design/mvp-minimal-design.md)）
> 方法：三方原文逐节对比——原文均已快照至本目录（仓内可追溯），提炼体裁公约数、各家独有手法与分歧轴，映射到本项目 D1–D9
> 一手来源：三份快照同目录存放，检索日期 2026-08-26（详见附录 A）

## 0. TL;DR

三方样本代表 SKILL 建设的三种流派：**GitHub 官方 security-review = 推理型**（数据流追踪 + 分册检索键），**Jeffallan security-reviewer = 编排型**（工具命令 + 双清单 + 元数据接口），**review-spec = 纪律型**（顺序禁令 + 隔离模式 + 记忆闭环）。三者共享 8 条体裁公约数（触发器前置元数据、瘦壳+分册、有序流程、机器可读分类、file:line 强制、输出契约先行、具名自检阶段、人在环边界）；分歧由「有无外部锚点」与「广度 vs 深度」两根轴解释。对 MVP 的净结论：**取官方版的步骤–分册绑定与负结果契约、Jeffallan 版的四项机制（白名单/双清单/golden 样例/CWE 外锚）、review-spec 的三条纪律（spec-before-code/隔离四属性/完成定义）**，共 10 条吸收点，全部落到具体文件（§5）。

## 1. 三方定位

| | 官方 security-review¹ | Jeffallan security-reviewer² | review-spec³ |
|---|---|---|---|
| 流派 | 推理型扫描器 | 工具编排型专家 | 对照型评审 |
| 正文体量 | 9,094 B | 4,878 B | 122 行 |
| 结构 | 正文 + references/ 五分册 | 正文 + references/ 六分册 | 单文件 + 三份过程分册外链 |
| 触发方式 | description 枚举漏洞类型 × 语言 × 用户话语 | metadata.triggers 关键词 + description | 显式命令 + 自然语言兜底 |
| 确定性工作 | 描述性提及（读 lockfile 清单） | **内联具体命令**（semgrep/gitleaks/trivy…） | 目录探测 |
| 记忆闭环 | 无 | 无 | 有（查询 + 回写 kk:arch-decisions） |

## 2. 体裁公约数（三方 DNA）

以下 8 条在三方全部出现，可确证为此类 SKILL 的体裁标准而非某家偏好：

1. **触发信息前置到元数据**。description 是给调度方读的路由键，不是给人看的简介。官方版甚至把用户可能说的话写进去（"is my code secure?" / "audit this codebase"）——触发匹配不只对技术词汇，也对自然语言请求。
2. **身份定调在程序之前**。开篇一句话给模型身份和行为标准（"像安全研究员一样推理" / "systematically compare"），后续工作流是该身份的展开。
3. **有序工作流 + 先后禁令**。步骤严格编号，关键处用禁令句式约束顺序（官方版 "Follow these steps **in order**"；review-spec 的 "spec before code" 禁止提前读实现代码——顺序本身承载防锚定偏差设计，不只是流程描述）。
4. **分类体系全部机器可读**。severity 各级带具体例子而非抽象形容词（官方 CRITICAL = "SQLi, RCE, auth bypass"）；finding 用固定类型码；confidence 强制附判定理由。可读分类只影响人，机器可读分类才能进门禁与 metrics（D1 的前提）。
5. **file:line 证据强制**。三家均要求 finding 附精确位置与代码片段；无位置证据的输出不合格。
6. **输出契约先行**。输出格式在工作开始前锁死：官方版要求汇总表第一 + 逐条 confidence；Jeffallan 版给四段式模板 + 一个全字段 golden 样例；review-spec 用 Required Outputs checklist 作为 skill 自身的完成定义。
7. **FP 抑制是具名执行阶段**。官方版 Step 6 self-verification 给出五子步（fresh eyes 重读→问"是否真可利用/漏了什么 sanitize"→查上游框架/middleware 是否已处理→降级或丢弃→定级）；review-spec 有 self-check + confidence 分档（speculative 不报）。自检不是美德要求，是流程中的具名环节（D4 同构）。
8. **人在环边界显式声明**。官方版 patch 提案必须附带原句 "**Review each patch before applying. Nothing has been changed yet.**"，Output Rules 写死 "Never auto-apply any patch"；Jeffallan 版 "Confirm findings with stakeholder before finalizing"、active testing 前验证书面授权。

结构性公约数：**三家均为「瘦正文 + references/ 分册按条件加载」**。正文只留流程与契约，检测细节外置——渐进披露控制 prompt 预算，即 D5"控制 prompt 长度就是控制误报率"在 skill 形态上的实现。

## 3. 各家独有手法

### 3.1 官方 security-review（推理型的贡献）

- **步骤–分册绑定**：每个工作流步骤内嵌"此步读哪本分册"指令（Step 1 → language-patterns.md，Step 2 → vulnerable-packages.md…），条件加载不是末尾的附录清单，而是织进流程；文末 Reference Files 再为每册附 **grep 检索键**（如 secret-patterns.md ← `API key, token, entropy, .env`），模型可按需检索定位。
- **跨文件数据流独立成阶段**（Step 5）：入口点→危险 sink 的全链路追踪单独安排在逐文件扫描之后，专捕单文件视角看不见的漏洞。
- **负结果输出契约**：代码干净时必须明说 "No vulnerabilities found" 并列出扫了什么范围——沉默不算通过，负结果也是一等公民输出。

### 3.2 Jeffallan security-reviewer（编排型的贡献）

- **字段级 frontmatter 元数据**：`allowed-tools: Read, Grep, Glob, Bash`（**工具白名单声明式收权**）、`metadata.triggers`（触发词独立成字段）、`role/scope/output-format` 类型化字段、`version`、`related-skills`（skill 间路由图）。调度方可纯靠元数据路由，不读正文。
- **MUST DO × MUST NOT DO 双清单**：十条正面 + 八条负面，全祈使句短句。负面清单尤其值钱（"Assume frameworks handle everything" ❌），正面要求模型会自行脑补边界，禁止项不会。
- **golden finding 样例**：FIND-001 全字段示例（ID/severity 带 CVSS 分/file:line/描述/影响/修复前后代码对照/CWE+OWASP 引用）。few-shot 锚定格式远强于 schema 描述。
- **外部分类法做严重度锚**：severity 挂 CVSS，finding 引用挂 CWE + OWASP 编号——跨团队可比、可与外部工具与 benchmark 对账。

### 3.3 review-spec（纪律型的贡献）

- **spec-before-code 顺序禁令**："加载 spec 文档并完成 profile 检测前，禁止读实现代码、禁止 grep 代码库"——防止先看代码再反推偏差的锚定污染。唯一允许的早期接触是目录名列举（够驱动 profile 检测，不够 pattern-match）。
- **隔离模式的四属性写法**：isolated mode（fresh subagent）文档同时标注成本 / 隔离度 / 降级路径 / 适用时机——D2 fresh-context 派发的现成文档范式。
- **记忆查询 + 回写闭环内置**：评审第 2 步先查已知的有意偏离索引（避免把 arch-decision 误报为 SPEC_DEV），第 9 步把用户确认的有意偏离回写索引。ANDM 飞轮在 skill 层的原型：召回注入与 propose 回写的位置都应长在 skill 流程内，不依赖调用方。
- **profile 槽位扩展**：IaC 等领域 profile 可注入阶段槽位，且给出类型码语义映射规则（声明式制品缺失 = MISSING_IMPL 而非 DOC_INCON）——领域扩展不改骨架。

## 4. 分歧轴与取舍

- **推理 vs 编排 vs 纪律**：官方版赌 LLM 推理质量（原则 + 数据流），Jeffallan 版赌工具编排 + 约束清单，review-spec 赌流程纪律 + 记忆闭环。对本项目：task-reviewer 的 conformance 通道本质是对照型（review-spec 同构），correctness 通道接近扫描型——**纪律层照抄 review-spec，检测层借官方版，机制件取 Jeffallan 版**。
- **外部锚点有无决定结构**：对照型必须有双向 finding 与隔离模式（否则作者自评必然偏）；扫描型必须有覆盖清单与数据流（否则退化为 pattern-match）。
- **广度 vs 深度**：Jeffallan 版一把抓渗透/云/合规，单点深度被摊薄，且无 confidence 分档、无降级路径——**只取其机制，不模仿其大而全**。

## 5. 对 MVP 的吸收清单（10 条，逐条有落点）

| # | 来源 | 机制 | MVP 落点 |
|---|---|---|---|
| 1 | Jeffallan | `allowed-tools` 白名单进 frontmatter | `agents/task-reviewer.md` 头部（§2.3"reviewer 只读"的实现方式） |
| 2 | Jeffallan | 输出纪律改 MUST / MUST NOT 双清单 | `templates/reviewer-prompt.md` |
| 3 | Jeffallan | 内嵌一条全字段 golden finding | 同上；素材直接用 `rules/scenarios/*/cases/golden.json` |
| 4 | Jeffallan | findings 加 `refs: ["CWE-476", …]` 外锚字段 | 工件 schema §2.1；打通 MITRE Top 25 与回放基准 |
| 5 | 官方 | 步骤 ↔ 分册绑定 + 每册检索键 | `review-package.sh` 在 context.md 头部生成"命中场景 → checklist → 触发路径"索引表 |
| 6 | 官方 | 负结果契约（CLEAN 也须记扫描范围） | 工件 CLEAN 时仍记 `spec_ref` + 命中场景列表——metrics 才有分母可算 |
| 7 | 官方 | 自检五子步（尤其"查上游是否已处理"） | correctness 通道的自检清单（D4 的 prompt 层实现） |
| 8 | review-spec | spec-before-code 顺序禁令 | prompt 模板明确"先读 spec 段落，后读 diff" |
| 9 | review-spec | 隔离模式四属性（成本/隔离/降级/适用） | D2 派发机制的文档模板 |
| 10 | review-spec | Required Outputs 完成定义 | `/sdd-review` 命令体末尾加完成 checklist |

## 6. 存疑项与边界

- 两份远端 SKILL 仅快照本体，`references/` 分册未拉取；若 task-reviewer 要借鉴官方 vuln-categories.md 的类别组织方式，届时再补快照。
- Jeffallan 版 `related-skills` 指向同仓另外 7 个 skill，其生态质量未逐一验证；本笔记仅取该文件自身机制。
- 官方版 frontmatter 无 author 字段，来源归属以聚合仓 github/awesome-copilot 为准。
- 三方均为通用技术场景；任何 checklist 内容写入本项目规则库前须过一遍业务口径（呼应 MVP 设计 §2.4 口径注意）。

---

**附录 A：信源**

| 快照 | 上游 | 说明 |
|---|---|---|
| [security-review-awesome-copilot/SKILL.md](security-review-awesome-copilot/SKILL.md) | github/awesome-copilot @ main · `skills/security-review/SKILL.md` | 9,094 B，检索 2026-08-26 |
| [security-reviewer-jeffallan/SKILL.md](security-reviewer-jeffallan/SKILL.md) | Jeffallan/claude-skills @ main · `skills/security-reviewer/SKILL.md` | v1.1.1，MIT，4,878 B，检索 2026-08-26 |
| [review-spec/SKILL.md](review-spec/SKILL.md) | 补充卷已收录的一手快照 | 本项目 conformance 类型码出处（补充卷 §2.2） |

关联决策：D1（机械门禁←公约数 4）、D2（fresh context←3.3 隔离模式）、D4（FP 抑制←公约数 7）、D5（prompt 预算←结构性公约数）、D9（人在环←公约数 8）。
