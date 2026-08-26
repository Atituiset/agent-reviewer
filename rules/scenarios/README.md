# 场景库：插拔契约

每个场景 = 一个目录（MVP 设计 §2.4.1 三元组）：

```
rules/scenarios/<key>/
├── checklist.md   # 注入 reviewer 的检测清单
├── meta.yaml      # {cwe, name, severity_default, languages, origin}
└── cases/         # 回放基准样本槽位（pos-*/neg-* + golden.json），团队历史缺陷案例迁入处
```

## 给团队资产留的槽位

1. **新场景接入（3 步）**：建 `<key>/` 目录放三元组 → `../registry.json` 加一行 glob 映射 → 完成。无需改任何脚本。
2. **迁移现有场景 prompt**：prompt 中的检测项整理进 `checklist.md`「检测信号」节即可；`meta.yaml` 的 `origin: team-asset` 标记来源；回放案例放入 `cases/`。
3. **`cases/` 槽位**：MVP 期允许为空。迁入格式见 MVP 设计 §2.4.1（`pos-001/diff.patch + golden.json`、`neg-001/diff.patch`）；`scenario-replay.sh` 检测到有 cases 的场景才纳入回放。

## 路由语义

- registry 一条规则命中即注入该行全部场景；一个路径命中多行时**场景取并集**
- `default` 场景对所有文件生效（兜底清单）
- `verify-artifact.sh` 会校验 finding 引用的 scenario 键存在于本目录——防幻觉场景名

## 口径注意（MVP 设计 §2.4）

现有 `origin: mitre-top25 / project-scenario / builtin` 的清单只含通用技术模式；团队私有业务口径一律走 `origin: team-asset` 场景承载，不混写。

## 环境要求

确定性脚本使用 Python 虚拟环境（仅 stdlib）：首次执行 `scripts/setup-env.sh` 创建 `.venv`；所有脚本自动优先用 `.venv/bin/python`，未创建时回退系统 `python3`。
