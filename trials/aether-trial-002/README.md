# 试验证据卷 · aether-trial-002

> AetherStack M16-M22 **真实新代码**（非播种）的首次 SKILL 场景库验证。日期：2026-08-27。

## 出处

| 项 | 值 |
|---|---|
| 目标仓 | `~/Projects/AetherStack`（master） |
| 被审变更 | commit `8394245`（M16-M22）的 `stack/` C++ 改动：52 文件，+6929/-531 |
| 基线 | `ea63c7f`（M15 文档同步点） |
| 场景库 | `rules/scenarios/`（14 个 SKILL.md，registry 由 frontmatter 生成） |
| 评审方式 | 确定性路由 → 风险抽样 5 文件 → 5 个并行 fresh-context 场景评审 subagent → 主控逐条读码核实 |

## 文件清单

| 文件 | 内容 |
|---|---|
| **`REVIEW.md`** | **检视报告（给人看的最终结论）：4 条 finding 逐条含位置/证据/修复建议 + 3 文件阴性记录** |
| `review-artifact.json` | 门禁工件：ISSUES_FOUND，4 条 finding（ruling: pending-team-triage）+ 阴性结果 |
| `diff.patch` | 被审变更原文（`git diff ea63c7f..8394245 -- stack/`，368 KB） |
| `changed-files.txt` | 52 个变更 C/C++ 文件清单 |
| `routing.txt` | 确定性路由输出（场景 × 文件覆盖矩阵汇总） |

## 完整性链

```
sha256sum diff.patch  →  6485c5bd180598544981f1f2bc261adc5db3c04356681496ac7b9e125aa7d170
grep diff_hash review-artifact.json  →  同值
```

## 与 aether-trial-001 的关系

trial-001（2026-08-26）是**播种缺陷**的端到端机械链路验证；trial-002 是 SKILL 格式场景库对**真实新代码**的首次检出验证——4 条真实 finding（cwe-125 越界读 / cwe-190 序号回绕 / cwe-401 ×2）+ 3 个干净文件零误报。4 条 finding 待 AetherStack 团队 triage。
