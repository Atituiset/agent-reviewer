# agent-reviewer · MVP 实施分支

> 本分支只含 **MVP 文档与源码**。调研三卷、复用性分析、ANDM 架构设计与论文 PDF 均在 `main` 分支（设计基线 tag `v0.1`），本文档引用的出处（报告一/二、补充卷、ANDM §x）请回 `main` 查阅对应章节。

## 必读文档（唯一）

[docs/design/mvp-minimal-design.md](docs/design/mvp-minimal-design.md) —— 实施契约：4 组件（review-gate / reviewer / memoryd / `/sdd-review`）、工件格式、门禁规则、验收标准。**§5 验收 checklist 直接当测试用例清单用。**

## 目录结构（MVP 设计 §1）

```
mvp/
├── commands/            # /sdd-review 命令
├── agents/              # task-reviewer subagent 定义
├── hooks/               # pre-commit 门禁 hook
├── rules/               # registry.json 场景路由 + scenarios/ CWE 键控三元组
├── scripts/             # review-package / verify-artifact / memory-{propose,approve,recall}
├── templates/           # reviewer-prompt / distiller-prompt
└── docs/design/         # mvp-minimal-design.md
```

目录已建骨架，组件按序填充：

1. 规则资产：`rules/registry.json` + 首批场景三元组（checklist/meta/cases）
2. 门禁：`verify-artifact.sh` → `pre-commit-gate.sh`（验收前 6 条）
3. 记忆链路：memoryd 三命令 + SQLite schema（§2.5）
4. 评审器：`task-reviewer.md` + `review-package.sh` + templates（吸收点清单见 main 分支 `references/primary-sources/skill-construction-notes.md` §5）
5. 串联：`/sdd-review` 主流程 + metrics 埋点（`.review/metrics.jsonl`）

## 验收

以 MVP 设计 §5 十条为准；每条对应一次可独立演示的验证。
