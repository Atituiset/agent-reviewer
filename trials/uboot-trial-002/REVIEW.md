# 检视报告 · uboot-trial-002（SKILL 格式转换后回归评审）

> 被审变更：`common/cli.c` 新增 `cli_build_banner()`（+19 行，[diff.patch](diff.patch)）
> 评审方：task-reviewer · 日期：2026-08-27
> **清单来源：转换后的 `rules/scenarios/*/SKILL.md`**（每条 finding 标注命中的清单条目）
> **结论：ISSUES_FOUND —— 3 条 finding（2 important / 1 minor），与格式转换前 uboot-trial-001 的评审结果完全一致**
> 机器可读工件：[review-artifact.json](review-artifact.json) · diff_hash `7e7b6ad4…c582`（与 trial-001 同 diff）

## 评审范围

- 场景（确定性路由，11 个）：cwe-125、cwe-190、cwe-20、cwe-362、cwe-401、cwe-416、cwe-476、cwe-78、cwe-787、cwe-798、default
- spec_ref：无（试验件无对应 spec）

## Findings

### ① important · security · cwe-787 —— 无界 strcpy 进栈缓冲（置信度 95%）

**位置**：`common/cli.c:361`

`strcpy(scratch, board)`，`scratch` 为 `char[32]` 栈缓冲，`board` 长度无约束，≥32 字节即摧毁栈帧。

**命中清单条目**：`cwe-787/SKILL.md` 检测信号 #1「memcpy/strcpy/sprintf 族目标缓冲区大小与源长度未核对」。

**修复建议**：去掉 scratch 中转，直接 `snprintf(banner, size, "%s#", board)`。

**ruling**：播种缺陷（试验件），不合并。

### ② important · bug · cwe-476 —— malloc 返回值未判空直传 snprintf（置信度 92%）

**位置**：`common/cli.c:362`

`malloc` 返回值未判空即作为 `snprintf` 写入目标；分配失败时写地址 0（上游 `lib/vsprintf.c:583-585` 的 `vsnprintf_internal` 无 NULL 保护；树内惯例见 cli.c:141-143）。

**命中清单条目**：`cwe-476/SKILL.md` 检测信号 #1「malloc/calloc/new 及各类 find/get/lookup 返回值未判空即解引用」。

**ruling**：播种缺陷（试验件），不合并。

### ③ minor · bug · MISSING_IMPL —— 新导出函数无原型、全树零调用（置信度 85%）

**位置**：`common/cli.c:356`

未在 `include/cli.h` 声明原型且全树无调用方，导出即死代码。

**命中清单条目**：`default/SKILL.md`「变更面：是否有死代码被引入」。

**ruling**：评审判断正确（真实增量发现，非播种）；随分支回滚自然消解。

## 与 trial-001 的对照（格式转换回归结论）

| 维度 | trial-001（旧 checklist 格式） | trial-002（SKILL 格式） | 结论 |
|---|---|---|---|
| finding 数 | 3 | 3 | 一致 |
| 播种缺陷命中 | 2/2（cwe-787、cwe-476） | 2/2 | 一致 |
| 行级锚点 | 361 / 362 / 356 | 361 / 362 / 356 | 一致 |
| 真实增量发现 | MISSING_IMPL ×1 | MISSING_IMPL ×1 | 一致 |
| 场景路由数 | 8 + default（旧 registry） | 11（新 registry，并集语义含 cwe-20/78/798） | 见注 |

注：路由数差异来自新格式下 cwe-20/cwe-78/cwe-798 按 languages 正确命中 C 文件（并集语义的预期行为），其中 cwe-78 对本文件为噪音（二级收敛候选，见 docs/validation 报告遗留项 1）。

**结论：场景库 SKILL 格式转换后，端到端评审结果与转换前完全一致——格式迁移无功能回归。**
