# u-boot 端到端试验记录（2026-08-26）

> 目标：验证 MVP 组件链在真实大型 C 仓上的机械行为。目标仓 `~/Projects/testbeds/u-boot`
> （v2026.07 @ ece349ad），试验分支 `review-gate-trial`，会话 `uboot-trial-001`。
> 方法：向 `common/cli.c` 追加 20 行函数 `cli_build_banner()`，**播种两个已知模式缺陷**
> （无界 `strcpy` 进栈缓冲；`malloc` 不判空即用），评审后完整还原目标仓。
> 复现步骤见 [trial-guide.md](trial-guide.md)。
> 原始工件（diff.patch / 门禁工件 / metrics / 记忆库导出）已归档于 [trials/uboot-trial-001/](../trials/uboot-trial-001/README.md)，含 diff_hash 完整性链与独立复核方法。

## 结果总览

| 步骤 | 动作 | 期望 | 实测 |
|---|---|---|---|
| T0 | 无工件直接 commit | 拒绝 rc=2 | ✅ E_PARTIAL_STAGE + E_NO_ARTIFACT，deny reason 附修正提示 |
| T1 | review-package | 场景路由命中 | ✅ `common/cli.c` → 8 个 C 系场景 + default；记忆召回空；无 spec 标注 |
| T2 | fresh-context subagent 评审 | 检出播种缺陷 | ✅ 两处均检出（见下）；**额外发现第三个未播种问题** |
| T3a | ISSUES_FOUND 工件过闸 | 拒绝 rc=2 | ✅ E_VERDICT（3 条未解决） |
| T3b | ESCALATED + 逐条 ruling | 放行 rc=0 | ✅ verify OK + gate 放行 |
| T4 | propose→approve→recall | 治理语义正确 | ✅ 无 file:line 拒收；quarantine 不出现在召回；approve 后按模块 GLOB 召回；不相关路径为空 |
| T5 | metrics.jsonl | 全程留痕 | ✅ `deny[PARTIAL,NO_ARTIFACT] → deny[E_VERDICT] → allow[artifact-ok]` |

## 评审质量（task-reviewer subagent，fresh context，14 次工具调用，约 4 分钟）

| # | finding | 行号 | severity/confidence | 判定 |
|---|---|---|---|---|
| 1 | `strcpy(board)` 进 `char[32]` 无界拷贝 | common/cli.c:361 | important / 95% | **命中播种缺陷①**（cwe-787，refs 带 CWE-120） |
| 2 | `malloc` 返回值直传 snprintf 无判空 | common/cli.c:362 | important / 92% | **命中播种缺陷②**（cwe-476） |
| 3 | 新导出函数在 include/cli.h 无原型且全树零调用方 | common/cli.c:356 | minor / 85% | **真问题，非播种**（MISSING_IMPL 集成缺口） |

亮点：

- **行级锚点全部精确**；finding #2 给出了上游证据链——`lib/vsprintf.c:583-585` 的
  `vsnprintf_internal` 无 NULL 保护（分配失败 = 写地址 0），并引用同文件既有惯例
  （`run_command_list()` cli.c:141-143 判空）佐证"违反树内约定"
- 修复建议具体可落地（去掉 scratch 拷贝、直接 `snprintf(banner, size, "%s#", board)` 并判空返 NULL）
- 无风格类噪音；verdict 诚实报 ISSUES_FOUND 而非凑数 CLEAN

## 结论与后续

- 机械链路（门禁/工件五规则/记忆治理/metrics）在真实大仓上零故障
- 检出能力初步信号积极：2/2 播种命中 + 1 个真实增量发现；单样本不构成 precision/recall 结论，
  待 `cases/` 回放基线建立后批量度量（MVP 设计 §2.4.2）
- 试验残留已归档：原始工件入 `trials/uboot-trial-001/`，播种提交推 fork（`review-gate-trial@41dd94c8`）；目标仓本地 runtime 目录可随时按 trial-guide 清理节还原
