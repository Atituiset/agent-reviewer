# uboot-trial-002：场景库 SKILL 格式转换回归验证

> 日期：2026-08-27
> 性质：格式转换回归验证（非盲测）。盲测检出能力见 [uboot-trial-001](../uboot-trial-001/README.md) 与 [docs/trial-u-boot.md](../../docs/trial-u-boot.md)
> 完整报告：[docs/validation/uboot-skill-format-validation.md](../../docs/validation/uboot-skill-format-validation.md)

## 验证对象与环境

- 场景库：`rules/scenarios/`（14 个 SKILL.md，commit `2f7881f` 完成格式转换）
- registry：`scripts/build-registry.sh` 由 frontmatter 生成（快照见 `registry-snapshot.json`）
- 目标：`~/Projects/testbeds/u-boot` 试验分支 `review-gate-trial@41dd94c8` 的播种缺陷 diff（`common/cli.c`，播种 cwe-787 + cwe-476）

## 归档工件

| 文件 | 内容 |
|---|---|
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

结论：**格式转换无路由损失、无覆盖损失**。两个播种缺陷均命中对应场景主清单第一条（映射表见完整报告 V2 节）。遗留：cwe-78 对纯 C 文件的噪音路由（二级收敛候选）；批量 precision/recall 待 cases/ 回放基线。
