# distiller-prompt（评审结论 → 记忆提案的提炼模板）

> 输入：task-reviewer 工件中 severity ∈ {critical, important} 且 resolved=true 的 findings
> 输出：memory-propose.sh 的 stdin JSON 数组（每条一个提案）

把每条已修复的高严重度 finding 提炼为一条可复用的团队记忆：

- `content`：一句话描述缺陷**模式**（非个案叙事），保留原 file:line 作为证据锚点
- `modules`：该模式适用的模块 glob（从 finding.file 归纳，宁窄勿宽——错召比漏召危害大）
- `bound_paths`：精确文件路径数组（失效引擎 V1 消费；MVP 仅记录）
- `evidence`：{"commit_sha": "...", "review_artifact": "<diff_hash 前 8 位>"}

拒答条件：无法归约为通用模式（一次性的笔误/配置失误）→ 跳过该条，不硬造。
质量红线：无 file:line 的提案会被 memory-propose.sh 拒收（E_NO_EVIDENCE）。
