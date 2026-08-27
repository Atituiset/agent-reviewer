# 试验证据卷 · aether-trial-001

> 目标仓 AetherStack（用户自有，电信 C++ 栈）上的端到端验证。记录文档待补；本卷为原始工件。

## 出处与远端追踪

| 项 | 值 |
|---|---|
| 目标仓 | `~/Projects/AetherStack`（master @ `ea63c7f`） |
| 远端 | https://github.com/Atituiset/AetherStack |
| 试验分支 | [`trial/review-gate`](https://github.com/Atituiset/AetherStack/tree/trial/review-gate) @ [`b287bcd`](https://github.com/Atituiset/AetherStack/commit/b287bcd367666ca12747832f991a1b5f93e26ec3)（**勿合并**） |
| 播种文件 | [stack/nas/src/nas_messages.cpp](https://github.com/Atituiset/AetherStack/blob/b287bcd367666ca12747832f991a1b5f93e26ec3/stack/nas/src/nas_messages.cpp) 追加 `make_padding_frame()`（+22 行） |
| 会话 | `aether-trial-001` |
| 日期 | 2026-08-26 |

## 文件清单

| 文件 | 内容 |
|---|---|
| **`REVIEW.md`** | **检视报告（给人看的最终结论）：5 条 finding 逐条含位置/证据/修复建议/ruling** |
| `diff.patch` | 被审变更原文（T1 打包时捕获） |
| `review-artifact.json` | 门禁工件终态：ESCALATED，5 条 finding 各带 ruling |
| `context.md` / `scenarios.json` | 评审输入包（命中 8 个 C/C++ 场景 + default） |
| `metrics.jsonl` | 门禁轨迹：豁免放行(19行) → deny(NO_ARTIFACT)×2 → allow(artifact-ok) |
| `memory-dump.sql` | 团队记忆库终态（4 条提案入 quarantine，1 条已审 active） |

## 完整性链

```
sha256sum diff.patch  →  ad5ea812d5a8f7df5d7f234e59fabf2f0d33e9ffab562f346cbbe41dbf537618
grep diff_hash review-artifact.json  →  同值
```

重建被审状态：`git checkout b287bcd^` → 应用 `diff.patch` → `git diff HEAD | sha256sum` 应得同一哈希。

## 评审结果速览

| # | 位置 | 级别 | 内容 | 判定 |
|---|---|---|---|---|
| 1 | :29 | critical | decode 收尾 `}` 被吞，新函数嵌套定义，编译失败（评审器以 g++ -fsyntax-only 实证） | **非播种真缺陷**——播种 Edit 自身引入，评审器抓出 |
| 2 | :35 | important | cwe-401 early-return 泄漏路径① | 播种命中 |
| 3 | :38 | important | cwe-401 泄漏路径② | 播种命中 |
| 4 | :33 | important | cwe-476 malloc 不判空即写入 | 播种命中 |
| 5 | :27 | important | EXTRA_IMPL 试验脚手架驻留产品目录、零调用无声明 | 对种子本身的元发现 |

## 备注

- 首次播种仅 19 行，落进 <20 行豁免线未被拦——豁免机制实测有效；复现请 ≥20 行
- 目标仓 `.gitignore` 不含 `.review/`，`git add -A` 会把运行时 metrics 卷进 diff，需先加 `.git/info/exclude`（本仓已验证此坑）
- 本地工作区已还原 master；试验记录由远端分支 + 本证据卷共同承载
