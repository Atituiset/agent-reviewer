---
description: 任务级评审最短闭环——打包输入 → 派发 fresh-context reviewer → 处置 findings → 写工件 → 记忆提案（MVP 设计 §3）
---

# /sdd-review

按顺序执行以下六步。**你（controller）负责编排与落盘，绝不替 reviewer 评审。**

## 1. 打包

```bash
scripts/review-package.sh --spec openspec/changes/<当前change名>   # 无 change 时省略 --spec
```

记录输出的包目录 `$PKG`，并计算 `DIFF_HASH=$(git diff HEAD | sha256sum | cut -d' ' -f1)`。

## 2. 派发

用 `templates/reviewer-prompt.md` 填充占位符（{{PACKAGE_DIR}}=$PKG、{{SPEC_REF}}、{{ROUND}}），
派发 **task-reviewer subagent**（fresh context，不携带本会话历史）。

## 3. 处置 findings

向用户呈现 findings → 修复或 dispute → 全部 resolved 进入第 4 步。
conformance 类 dispute 由用户裁决；裁决为"有意偏离"的，在 finding.ruling 留痕。

## 4. 工件落盘与熔断

- 第 {{ROUND}} 轮全清 → verdict=CLEAN
- 仍有残留且 ROUND=2 → verdict=ESCALATED：escalated=true，每条残留 finding 补人工 ruling（无 ruling 视为本命令失败）
- 否则修复后回到第 2 步（ROUND+1）

写入 `.git/review-gate/<session-id>.json`（session id 取自当前会话；拿不到则写 `.review/last-review.json`），
diff_hash/reviewed_at 由 controller 填充真实值，scenarios_scanned 取自 $PKG/scenarios.json。

自校验：`scripts/verify-artifact.sh` 必须通过再进入第 5 步。

## 5. 记忆提案（自动）

对工件中 severity ∈ {critical, important} 且 resolved=true 的 findings，按 `templates/distiller-prompt.md`
提炼提案数组，逐条管道给 `scripts/memory-propose.sh`；被 E_NO_EVIDENCE 拒收的条目原样报告用户，不得静默丢弃。

## 6. 提示审核

输出：「N 条记忆待审核（quarantine）。请 MDE 定期运行 scripts/memory-approve.sh <id>」，
并列出本次新提案的 id 与一句话内容。

## Required Outputs（完成定义，缺一即未完成）

- [ ] 评审工件已写入并通过 verify-artifact.sh
- [ ] 用户已确认每条 finding 的处置（修复 / dispute+ruling）
- [ ] 高严重度已修复项的 memory 提案已入 quarantine（或拒收原因已报告）
- [ ] 下一步提示已给出（审核队列 / 提交）
