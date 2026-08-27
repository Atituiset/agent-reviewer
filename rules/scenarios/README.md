# 场景库：插拔契约

每个场景 = 一个目录，标准 SKILL.md 格式（MVP 设计 §2.4/§2.4.1）：

```
rules/scenarios/<cwe-key>/
├── SKILL.md       # frontmatter：name / description / cwe / severity_default / origin / paths
│                  # 正文 = 注入 reviewer 的检测清单
├── references/    # 可选：深入检测项（渐进式披露，主清单不够用时由 reviewer 按需加载）
└── cases/         # 回放基准样本槽位（pos-*/neg-* + golden.json），团队历史缺陷案例迁入处
```

`paths` frontmatter 是确定性路由的唯一数据源：`scripts/build-registry.sh` 扫描全部 SKILL.md 生成 `../registry.json`（派生物，勿手改）。路由由脚本执行，模型不参与场景选择。

## 场景维护（3 步）

1. **新场景接入**：建 `<cwe-key>/` 目录放 SKILL.md（含 paths）→ 跑 `scripts/build-registry.sh` → 完成，无需改任何脚本
2. **修订清单**：直接改 SKILL.md 正文；新增 glob 则改 frontmatter `paths` 后重新生成 registry
3. **`cases/` 槽位**：MVP 期允许为空。迁入格式见 MVP 设计 §2.4.1（`pos-001/diff.patch + golden.json`、`neg-001/diff.patch`）；`scenario-replay.sh` 检测到有 cases 的场景才纳入回放

## 路由语义

- registry 一条规则命中即注入该行全部场景；一个路径命中多行时**场景取并集**
- `default` 场景对所有文件生效（兜底清单）
- `verify-artifact.sh` 校验 finding 引用的 scenario 键存在于本目录——防幻觉场景名

## origin 口径

`origin: mitre-top25 / project-scenario / builtin` 的清单只含通用技术模式；团队私有业务口径一律走 `origin: team-asset` 场景承载，不混写。

## 环境要求

确定性脚本使用 Python 虚拟环境（仅 stdlib）：首次执行 `scripts/setup-env.sh` 创建 `.venv`；所有脚本自动优先用 `.venv/bin/python`，未创建时回退系统 `python3`。
