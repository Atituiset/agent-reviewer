# 检视报告 · uboot-trial-001

> 被审变更：`common/cli.c` 新增 `cli_build_banner()`（+19 行，[diff.patch](diff.patch)）
> 评审方：task-reviewer（fresh-context subagent）· 日期：2026-08-26
> **结论：ESCALATED —— 3 条 finding（2 important / 1 minor），逐条 ruling 后放行（试验分支，不合并）**
> 机器可读工件：[review-artifact.json](review-artifact.json) · diff_hash `7e7b6ad4…c582`

## 评审范围

- 场景：cwe-787、cwe-476、cwe-125、cwe-401、cwe-416、cwe-190、default（7 个）
- spec_ref：无（试验件无对应 spec）

## Findings

### ① important · security · cwe-787 —— 无界 strcpy 进栈缓冲（置信度 95%）

**位置**：`common/cli.c:361`

`cli_build_banner()` 执行 `strcpy(scratch, board)`，其中 `scratch` 为 `char[32]` 栈缓冲。`board` 长度无任何约束，≥32 字节的输入即摧毁栈帧。

**证据**：refs CWE-787 / CWE-120；函数内无任何长度校验点。

**修复建议**：去掉 scratch 中转，直接 `snprintf(banner, size, "%s#", board)`。

**ruling**：播种缺陷（试验件），分支用后即焚，不合并。

### ② important · bug · cwe-476 —— malloc 返回值未判空直传 snprintf（置信度 92%）

**位置**：`common/cli.c:362`

`banner = malloc(CLI_BANNER_BUF)` 后未判空即作为 `snprintf` 写入目标。分配失败时写入地址 0。

**证据**：上游 `lib/vsprintf.c:583-585` 的 `vsnprintf_internal` 无 NULL 保护；且树内惯例要求判空（`run_command_list()`，cli.c:141-143）。

**修复建议**：判空并在失败时返回 NULL。

**ruling**：播种缺陷（试验件），不合并。

### ③ minor · bug · MISSING_IMPL —— 新导出函数无原型、全树零调用（置信度 85%）

**位置**：`common/cli.c:356`

`cli_build_banner()` 未在 `include/cli.h` 声明原型，且全树无任何调用方——导出即死代码，集成缺口。

**ruling**：评审判断正确（真实增量发现，非播种）；随分支回滚自然消解。

## 评审质量注记

- 行级锚点全部精确；finding ② 给出了跨文件上游证据链与树内惯例佐证
- 无风格类噪音；verdict 诚实报 ISSUES_FOUND 而非凑数 CLEAN
- 处置：T3a（未解决 finding 工件过闸）正确拒绝 → T3b（ESCALATED + 逐条 ruling）放行，门禁机械行为符合设计
