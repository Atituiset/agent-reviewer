# 试验证据卷 · uboot-trial-004：跨文件表驱动 FP 对照（2026-08-28）

> 试验仓 u-boot（19k 源文件）。试验件：入口判空（`common/cli.c:cli_trial_handle`）→ 跨文件 →
> 函数指针表（`lib/trial_engine.c:TRIAL_HANDLER_TBL`）→ 4 层转发 → 深处解引用（`render_line: frame->buf[0]`）。
> 目标：验证跨函数 + 跨文件 + 表分发场景下，模式 1（无索引）与模式 2（+codegraph）的差异。

## PR 与结果

| PR | 分支 | 模式 | run | annotations |
|---|---|---|---|---|
| [#2](https://github.com/Atituiset/u-boot/pull/2) | trial/fp-xfile-1 | 1 | 33171538589 | 4 |
| [#3](https://github.com/Atituiset/u-boot/pull/3) | trial/fp-xfile-2 | 2 | 33171516604 | 2（codegraph 调用 17 次） |

## 关键差异：同一个 cwe-476，两种证据深度

**模式 1**（`lib/trial_engine.c:29`）：「导出符号未判空即经函数指针表四层转发后深处解引用，**判空契约仅在被调用方所在 TU**」——结论对，但证据止步于「本文件内」。

**模式 2**（`lib/trial_engine.c:15`）的 reasoning 含完整跨文件回溯路径与断链点标注：

> 按 3.5 用 codegraph 回溯调用链 ≤10 跳：**render_line ← compose ← prepare ← accept ← TRIAL_HANDLER_TBL\[chan\](frame) ← trial_engine_render ← cli_trial_handle（判空）**。链在函数指针表 `lib/trial_engine.c:33` 处中断，静态不可判定 → 按纪律保留（PLAUSIBLE 并标注断链点）

并同时指出 `trial_engine_render` 是非 static 导出符号、绕过入口的调用方不受契约保护（契约级发现）。

## 非设计播种的真实缺陷（两模式均命中）

试验件本身带三处真实问题，全部被检出：

1. **不完整类型编译错误**（`common/cli.c:355`）：`struct trial_frame` 在 cli.c 仅前向声明、完整定义在 lib/trial_engine.c 文件私有——`frame->buf` 硬编译错误。**模式 2 用 `gcc -c` 最小复现验证后上报**（"最小复现已用 gcc -c 验证"）
2. **`#include "../include/common.h"` 引用不存在头文件**（模式 1 检出）：新版 u-boot 已移除该头文件
3. **构建集成缺失**：`lib/trial_engine.c` 未加入任何 Makefile（不会被编译）+ `cli_trial_handle` 全仓零调用——死代码（两模式的 default 基线均检出）

## 归档工件

两模式各含：`run-logs/`（全步骤日志）、`claude-execution-output.json`（评审轨迹，含 codegraph CLI 调用记录）、`review.sarif`。

## 结论

- 跨文件 + 表分发场景在 u-boot 量级真实复现：模式 2 的 codegraph 回溯跨越两个文件闭合到入口判空，并在表处按纪律标注断链——**「回溯 → 断链 → PLAUSIBLE」协议在真实大型 C 仓上按设计工作**
- 两模式都摸到了契约级问题（公开入口绕过判空），差异在**证据链的可信度与可读性**（模式 2 的 reasoning 点名了每一跳和断链位置）
- 评审的执行验证能力超预期：模式 2 对编译错误用 `gcc -c` 做了最小复现再上报——这正是「以证据而非声明来验证」的纪律
