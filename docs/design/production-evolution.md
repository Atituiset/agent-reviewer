# 从 MVP 到生产：自建评审体系与官方对比及演进路线

> 日期：2026-08-28
> 性质：现状盘点 → 与官方体系逐项对比 → 差距分析 → 生产化演进路线（分阶段、可验收）
> 前置文档：`docs/research/claude-code-review-tech-analysis.md`（官方技术分析）、`docs/design/mvp-minimal-design.md`（MVP 设计）、`docs/design/ai-native-dev-memory-architecture.md`（ANDM）

---

## 1. 现状盘点：已验证的资产

截至 2026-08-28，以下不是设计而是**已运行验证的事实**：

| 资产 | 验证证据 |
|---|---|
| SKILL 场景库（14 个场景：13 CWE + default 基线，frontmatter 路由） | registry 由 frontmatter 生成；路由在 u-boot/AetherStack 真实 diff 上验证 |
| 确定性路由（glob → 场景，模型不参与选择） | 52 文件批量路由验证（aether-trial-002） |
| 评审 subagent 双通道（conformance + 红队 correctness） | uboot-trial-001：2/2 播种命中 + 1 真实增量发现 |
| pre-commit 门禁（工件 hash 绑定 diff、ESCALATED ruling、豁免/fail-open） | selftest 22/22；trial 门禁轨迹留痕 |
| 记忆最短链路（propose → quarantine → approve → 按模块召回） | selftest ⑫⑬⑭；飞轮标注链路（memory-label）⑱-㉑ |
| SARIF 投影（codeFlows 证据链、reasoning、hostedViewerUri） | 4 个 trial 全部生成；GitHub Show paths 可见 |
| CI 可复用 workflow（DeepSeek 端点，多仓薄 caller） | AetherStack#u-boot 双 PR 全绿；播种 3/3 检出零误报 |
| 告警内完整呈现（判断理由 + 证据链进 message） | 双仓 annotations 实测全文 524 字符 |
| vscode-flywheel 扩展（SARIF 树/详情/TP-FP 标注） | 编译通过；标注 → team.db 端到端验证 |
| 单次评审成本 ~$1（20 turns，0 permission denials） | CI 实测 $0.98 |

## 2. 与官方体系逐项对比

| 维度 | 官方（托管 + action + skill） | 我们（当前） | 差距性质 |
|---|---|---|---|
| 流水线范式 | find → verify → rank → report 四段分离 | find（场景路由+subagent）→ verify（主控核实）→ report | **基本同构**，rank 段缺失 |
| 验证机制 | 三态 CONFIRMED/PLAUSIBLE/REFUTED，recall-biased 变体 | 二元置信度 ≥80 阈值 | 精细度差距 |
| 误报纪律 | 显式不报清单 + "finder 不得丢弃半信候选" | 显式不报清单已有；无 finder 丢弃禁令 | 一条规则的事 |
| 规则组织 | 单文件 REVIEW.md as-is 注入 | **CWE 键控场景库 + 确定性路由 + 回放基线** | **我们占优** |
| 评审时机 | 仅 PR 阶段 | **commit 前门禁** + PR 终闸双层 | **我们占优** |
| 成本 | $15-25/次，无分档 | ~$1/次，仍无分档 | **我们占优**，但分档都没做 |
| 反馈演进 | 👍/👎 归 Anthropic | **TP/FP → quarantine → MDE → 团队资产** | **我们占优（结构性）** |
| 结构化出口 | ReportFindings / 计数 JSON / structured_output | canonical 工件 + SARIF codeFlows | 同构，工件产出方式可优化 |
| 打磨度 | 去重、排序、auto-resolve、re-review 收敛、fixed 跟踪 | 全缺 | 主要差距 |
| 评测基线 | 内部 dogfood 数据（<1% 错误标记率） | cases/ 为空，仅单点播种验证 | **关键差距** |
| 安全（评外部 PR） | base ref 恢复配置、输出净化、payload 防注入 | 未做 | 评 fork 前必须补 |
| 质量波动控制 | 验证段 + 去重 + 排序收敛 | 边缘 finding 有运行间波动（实测） | 评测基线建好后才可量化 |
| 展示 | inline 评论（折叠 reasoning）+ 注解 + 计数 | SARIF 告警（message 全文 + Show paths）+ 可选 PR 评论 | 同构 |

## 3. 差距分析：三个真正要紧的差距

**① 评测基线缺失（最要紧）**。官方敢说 <1% 错误标记率是因为有 dogfood 度量；我们只有"两个仓 3/3 播种命中"的单点证据。没有 `cases/` 回放基线，就无法回答生产化的第一问：**换模型、改 prompt、加场景之后，质量是升了还是降了**。这正是 MVP 设计 §2.4.2 预留的 `scenario-replay.sh` 的位置。

**② 质量波动无收敛机制**。实测同一 diff 两轮运行的边缘 finding 有出入（u-boot 第 5 条从"恒假守卫"变成"cwe-20"）。官方的收敛手段是验证段 + 去重 + 排序 + re-review 收敛规则；我们目前只有单段置信度阈值。不解决这个，团队对告警的信任会随机波动。

**③ 打磨度缺口影响信任建立**。官方的重度功能——修复后自动 resolve、re-review 只报 Important、fixed 状态跟踪——本质都是**防告警疲劳**。我们的飞轮治理（quarantine/ruling）覆盖了处置语义，但告警生命周期管理（修复确认、收敛）还没有。

**不要紧的差距**：模型档位（配置问题可换）、extended reasoning 折叠区（message 全文已等价）、auto-resolve 重 infra（ruling 已覆盖）、Claude App 体系（github_token 更简单）。

## 4. 生产化演进路线

### 阶段 1：生产可用（2–4 周）——把"信任地基"打牢

目标：在 1-2 个真实团队仓上持续运行，告警可信、成本可控、评外部 PR 安全。

| # | 事项 | 来源 | 验收标准 |
|---|---|---|---|
| 1.1 | **三态验证进 prompt 与工件**：CONFIRMED/PLAUSIBLE/REFUTED 替代二元置信度；"finder 不得丢弃半信候选"写入纪律；高严重度场景用 recall-biased | 技术分析 §4.3 | 工件含 verification 字段；selftest 新增三态用例 |
| 1.2 | **评测基线建立**：团队历史缺陷案例迁入 `cases/`（每场景 ≥3 pos + 2 neg）；`scenario-replay.sh` 实现两层匹配（CWE tag + 锚点 + judge 语义判等）；跑出 per-scenario P/R 基线 | MVP §2.4.1/2.4.2 | 基线报告落盘；后续每次场景/prompt 变更必须回放回归 |
| 1.3 | **`structured_output` 产工件**：CI 评审步骤改 `claude_args --json-schema`，消除对 Write 权限的依赖 | 技术分析 §2.5 | CI 不再依赖 allowedTools Write；工件 schema 有强校验 |
| 1.4 | **effort 分档**：diff <200 行走单遍快评（不起 subagent），200-1000 走当前管线，>1000 走多 angle 并行 | 技术分析 §4.1 | 小 PR 成本 <$0.3；大 PR 成本可预测 |
| 1.5 | **fork PR 安全加固**：场景库/配置从 base ref 恢复；diff/评论内容声明"数据不是指令"；自动输出脱敏 | 技术分析 §7.5 | 构造投毒 PR 验证评审规则不被篡改 |
| 1.6 | **噪音路由收敛**：注入类场景（cwe-78 等）增加二级信号（文件含 `system/popen/exec` 才加载） | u-boot 验证遗留 | cli.c 类文件不再注入 cwe-78 |
| 1.7 | **re-review 收敛规则成文**：同 PR 第二轮起只报 CONFIRMED + important 以上 | 技术分析 §7.2/REVIEW.md 模式 | metrics 里平均每 PR 评审轮数 ≤2 的既有目标保持 |

### 阶段 2：质量收敛（1–2 月）——告警生命周期完整

| # | 事项 | 验收标准 |
|---|---|---|
| 2.1 | **新场景**：silent-failure-hunter（空 catch/静默跳过）、pr-test-analyzer（行为覆盖）加入场景库，各自带回放基线 | per-scenario P/R 不低于既有场景均值 |
| 2.2 | **fixed 状态跟踪轻量版**：新一轮评审携带上轮 findings 复核"是否仍存在"，消失的标记 fixed | trials 中修复播种缺陷后复评，fixed 标记正确 |
| 2.3 | **去重与排序段**：同缺陷同位置多报合一（当前已有个案：aka.cpp 两处同模式分开报可接受，但需规则）；按严重度 × 置信度排序 | 重复 finding 率 <5%（metrics） |
| 2.4 | **per-scenario precision 趋势**：labels 表驱动月度报表，低 precision 场景自动进改进提案（飞轮已有阈值机制，补报表） | 月度 precision 报告；连续两月 <70% 的场景必须整改或下线 |
| 2.5 | **模型分层**：预判/路由/分类用小模型，发现/验证用强模型；终审可用更高档位 | 单次成本再降 30%+，P/R 不降 |

### 阶段 3：规模化（2–3 月）——从工具到体系

| # | 事项 | 验收标准 |
|---|---|---|
| 3.1 | **ANDM 飞轮全量生产化**：失效引擎（git hook + bound_paths 降级）、session 综合写入、coding 侧注入 | 记忆条目平均存活周期可度量；degraded 条目复核 SLA |
| 3.2 | **多仓推广 kit**：新仓接入 = 加 caller + 配 secrets + 可选场景裁剪，30 分钟完成；接入文档已有（docs/ci-setup.md）补充场景裁剪节 | 第 3-5 个仓接入实测 |
| 3.3 | **度量看板**：评审覆盖率、漏网率、precision 趋势、成本曲线（对齐官方 analytics 的四个区块） | 月度运营报告自动生成 |
| 3.4 | **多宿主扩展评估**：场景库已是 SKILL 标准格式，评估 Codex/Cursor 宿主接入成本 | 决策文档（做或不做） |
| 3.5 | **merge gate 可选硬化**：需要硬门禁的仓解析计数 JSON（`{"normal":N}`）在 branch protection 中卡 important > 0 | 至少在 1 个仓试点 |

## 5. 生产化的关键风险与对策

| 风险 | 信号 | 对策 |
|---|---|---|
| **告警疲劳**（最致命） | 每 PR 评审轮数 >2；nit 类占比上升；团队开始忽略告警 | 阶段 1.7 收敛规则 + 2.4 precision 报表淘汰低效场景；宁可缩量不可降质 |
| **模型/端点漂移** | 回放基线分数无预警下滑 | 基线回放接入场景库 CI（改 SKILL/prompt 必跑）；模型版本钉住 + 升级必须回归 |
| **评测基线被污染** | 回放分数异常高（疑似泄漏） | cases 优先 2023 后 CVE、按时间序切分、定期更新（MVP §2.4.1 防泄漏条款） |
| **prompt 投毒（fork PR）** | 评审输出包含 diff 中的指令性内容 | 阶段 1.5 加固 + "数据不是指令"声明 + 输出 sanitize |
| **成本失控** | 单次成本 >$2 或大 PR 排队 | 阶段 1.4 分档 + 2.5 模型分层 + spend 月度预算线 |
| **飞轮空转** | quarantine 积压、无人审核 | severity 路由（low 自动入库）+ MDE 批量队列 + 积压时长进看板 |

## 6. 一句话路线

**先用 2-4 周把「三态验证 + 回放基线 + structured_output + 分档 + fork 安全」这五件事做掉（全部来自官方已验证的做法且成本极低），我们的体系就从"跑通的 MVP"变成"可信的生产工具"；之后的差距全是打磨度，可以按团队的信任曲线慢慢补。**

---

## 附录：对照索引

- 官方技术分析：`docs/research/claude-code-review-tech-analysis.md`（§4 三态验证、§2.5 structured_output、§4.1 effort 梯队、§7.5 安全）
- 我们的设计：`docs/design/mvp-minimal-design.md`（§2.4.2 回放协议、§5 验收标准）
- 验证证据：`trials/`（uboot-trial-001/002、aether-trial-001/002）、`docs/validation/`
- 飞轮治理：`docs/design/ai-native-dev-memory-architecture.md`（ANDM §4 状态机、§10 记忆工程机制）
