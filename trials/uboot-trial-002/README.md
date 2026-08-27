# uboot-trial-002：场景库 SKILL 格式转换回归验证

> 日期：2026-08-27
> 性质：格式转换回归验证（路由 + 覆盖映射 + **回归评审**；非盲测——播种缺陷已知，目的在于证明转换无回归）。盲测检出能力见 [uboot-trial-001](../uboot-trial-001/README.md) 与 [docs/trial-u-boot.md](../../docs/trial-u-boot.md)
> 完整报告：[docs/validation/uboot-skill-format-validation.md](../../docs/validation/uboot-skill-format-validation.md)

## 验证对象与环境

- 场景库：`rules/scenarios/`（14 个 SKILL.md，commit `2f7881f` 完成格式转换）
- registry：`scripts/build-registry.sh` 由 frontmatter 生成（快照见 `registry-snapshot.json`）
- 目标：`~/Projects/testbeds/u-boot` 试验分支 `review-gate-trial@41dd94c8` 的播种缺陷 diff（`common/cli.c`，播种 cwe-787 + cwe-476）

## 归档工件

| 文件 | 内容 |
|---|---|
| **`REVIEW.md`** | **检视报告（给人看的最终结论）：3 条 finding 逐条标注命中的 SKILL 清单条目，附与 trial-001 的逐项对照** |
| `review-artifact.json` | 回归评审门禁工件：ISSUES_FOUND，3 条 finding（含 `checklist_item` 清单条目映射） |
| `diff.patch` | 被审变更原文（与 trial-001 同 diff，sha256 `7e7b6ad4…c582`） |
| `routing-match.txt` | 路由验证输出：`common/cli.c` 命中 11 个场景，cwe-787 / cwe-476 在场 |
| `registry-snapshot.json` | 验证时使用的 registry（10 条路径规则，由 14 个 SKILL.md 生成） |

## 独立复核方法

```bash
# 在 agent-reviewer 仓库根目录（checkout 本 commit）
python3 - <<'EOF'
import json, re
# 用 registry-snapshot.json 重放 routing-match.txt 的匹配逻辑
# （glob 展开与 ** 语义见 routing-match.txt 头部注释对应的实现）
EOF
```

结论：**格式转换无路由损失、无覆盖损失、端到端评审结果与转换前完全一致**（trial-001 vs trial-002 逐项对照见 REVIEW.md）。两个播种缺陷均命中对应场景主清单第一条。遗留：cwe-78 对纯 C 文件的噪音路由（二级收敛候选）；批量 precision/recall 待 cases/ 回放基线。
