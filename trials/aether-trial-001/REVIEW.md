# 检视报告 · aether-trial-001

> 被审变更：`stack/nas/src/nas_messages.cpp` 追加 `make_padding_frame()`（+22 行，[diff.patch](diff.patch)）
> 评审方：task-reviewer（fresh-context subagent）· 日期：2026-08-26
> **结论：ESCALATED —— 5 条 finding（1 critical / 4 important），逐条 ruling 后放行（试验分支，不合并）**
> 机器可读工件：[review-artifact.json](review-artifact.json) · diff_hash `ad5ea812…7618`

## 评审范围

- 场景：cwe-125、cwe-190、cwe-362、cwe-401、cwe-416、cwe-476、cwe-78、cwe-787、default（9 个）
- spec_ref：无（试验件无对应 spec）

## Findings

### ① critical · bug · default —— decode 缺收尾大括号，翻译单元无法编译（置信度 98%）

**位置**：`stack/nas/src/nas_messages.cpp:29`

`make_padding_frame` 被嵌套定义在 `NasMessage::decode` 函数体内——`decode` 的闭合括号缺失。

**证据**：`g++ -fsyntax-only` 复现 `function-definition is not allowed here`（编译器实证，非推测）。

**ruling**：播种 Edit 误吞闭合括号——真实缺陷确认；分支用后即焚。

### ② important · security · cwe-401 —— early-return 路径内存泄漏（置信度 96%）

**位置**：`stack/nas/src/nas_messages.cpp:35`

tag 为空的 early-return 路径未 `free(frame)`：`malloc` 于 L32-33，唯一释放点在 L44，提前返回绕过释放。

**ruling**：播种缺陷（cwe-401，验证检出率用）。

### ③ important · security · cwe-401 —— 第二条泄漏路径（置信度 96%）

**位置**：`stack/nas/src/nas_messages.cpp:38`

body 超限的 early-return 同样泄漏：超限校验发生在 `malloc` **之后**，与 ② 同型。

**ruling**：播种缺陷（cwe-401 第二路径）。

### ④ important · security · cwe-476 —— malloc 未判空即作 memcpy 写入目标（置信度 84%）

**位置**：`stack/nas/src/nas_messages.cpp:33`

分配失败时 L40 对空指针写入，未定义行为。

**ruling**：播种缺陷（cwe-476）。

### ⑤ important · conformance · EXTRA_IMPL —— 试验脚手架落入产品源文件（置信度 88%）

**位置**：`stack/nas/src/nas_messages.cpp:27`

新增函数在头文件无声明、全仓零调用（diff 中 `TRIAL SEED` 注释自述）；`spec_ref=none` 本身有 AMBIGUOUS 风险。

**ruling**：对种子本身的元发现正确；分支将删除。

## 评审质量注记

- 检出 3 类播种缺陷（cwe-401 ×2 路径、cwe-476）外，**额外捕获播种操作本身引入的编译级真实缺陷**（①）——critical 级，且以编译器复现为证据而非推测
- finding ②③ 区分了两条同型泄漏路径并分别锚定行号，未合并含糊处理
- 门禁轨迹（metrics.jsonl）：豁免放行（19 行）→ deny(NO_ARTIFACT)×2 → allow(artifact-ok)，机械行为符合设计
