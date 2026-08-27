# 试验证据卷 · uboot-trial-001

> [docs/trial-u-boot.md](../../docs/trial-u-boot.md) 的原始工件附件。文档是叙述，本目录是证据。

## 出处

| 项 | 值 |
|---|---|
| 目标仓 | `~/Projects/testbeds/u-boot`（v2026.07） |
| 远端 | https://github.com/Atituiset/u-boot（fork） |
| 分支 | [`review-gate-trial`](https://github.com/Atituiset/u-boot/tree/review-gate-trial) @ [`41dd94c8`](https://github.com/Atituiset/u-boot/commit/41dd94c88122c0c2a87b48d8ef7792575265b3d9)（**勿合并**） |
| 播种文件 | [common/cli.c](https://github.com/Atituiset/u-boot/blob/41dd94c88122c0c2a87b48d8ef7792575265b3d9/common/cli.c) 追加 `cli_build_banner()`（+19 行） |
| 会话 | `uboot-trial-001` |
| 日期 | 2026-08-26 |

## 文件清单

| 文件 | 内容 | 来源 |
|---|---|---|
| **`REVIEW.md`** | **检视报告（给人看的最终结论）：3 条 finding 逐条含位置/证据/修复建议/ruling** | 由 review-artifact.json 渲染 |
| `diff.patch` | 播种改动原文（`common/cli.c` 新增 `cli_build_banner()`，含 cwe-787/cwe-476 两处已知缺陷） | `git diff ece349ad..41dd94c8 -- common/cli.c` |
| `review-artifact.json` | 门禁工件（ESCALATED + 3 条 finding 各带 ruling） | `.git/review-gate/uboot-trial-001.json` |
| `metrics.jsonl` | 门禁决策轨迹：deny(PARTIAL,NO_ARTIFACT) → deny(E_VERDICT) → allow(artifact-ok) | `.review/metrics.jsonl` |
| `memory-dump.sql` | 团队记忆库终态 SQL 文本（1 条 quarantine 未审 + 1 条 active 已审 by human-mde） | `memory/team.db` 导出 |

## 完整性链

工件中的 `diff_hash` 与 `diff.patch` 绑定，可独立复核：

```bash
sha256sum diff.patch        # 期望 7e7b6ad41a9dfac4a2afae8f397d9e6b528664a3b7306eb8a5ad47c7dca3c582
grep diff_hash review-artifact.json
```

重建路径：checkout `review-gate-trial@ece349ad` → 应用 `diff.patch` → `git diff HEAD | sha256sum` 应得同一哈希；即评审器看到的输入可逐字节复现。

## 备注

- 评审输入包原落 `/tmp/review-uboot-trial-001/`（context.md/scenarios.json），临时目录已清；输入侧由 `diff.patch` + registry 规则完全决定，可重建，故未另存
- 本卷归档后，目标仓本地的运行时残留（`.review/`、`memory/`、`.git/review-gate/`）可随时清理
