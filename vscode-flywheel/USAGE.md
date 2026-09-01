# Agent Reviewer Flywheel 使用文档

在 VS Code 中浏览评审管道产出的 SARIF 告警，并把人工结论（误报/真实问题）
回传给记忆飞轮。面向在任意代码仓（如企业内部 C/C++ 仓）上直接使用。

## 1. 安装

扩展不在公开 Marketplace，通过 VSIX 分发：

```bash
cd vscode-flywheel
npm install
npm run compile
npx @vscode/vsce package        # 生成 agent-reviewer-flywheel-0.1.0.vsix
```

然后在 VS Code 中：**Extensions → ⋯ → Install from VSIX…** 选择该文件。

开发调试：用 VS Code 打开 `vscode-flywheel` 目录按 **F5**，会启动一个加载了本扩展的
Extension Development Host。

## 2. 告警文件格式

扩展自动扫描工作区内所有 `*.sarif` 和 `*.jsonl` 文件（排除 `node_modules`），
文件变更时自动刷新。

### 2.1 `.sarif`

标准 SARIF 2.1.0 文档，告警取自 `runs[].results[]`。

### 2.2 `.jsonl`

每行一个 JSON 值，空行忽略。每行可以是：

- 一个完整的 SARIF 文档（含 `runs`），或
- 一个单独的 result 对象。

适合"一个被审文件对应一个 `.jsonl`，内含该文件的多个告警"的产出方式。

### 2.3 告警字段约定

每个 result 使用以下字段：

| 字段 | 用途 |
|---|---|
| `ruleId` | 规则名，树视图按此分组 |
| `level` | `error` / `warning` / `note`，决定图标 |
| `message.text` | 告警描述 |
| `locations[0].physicalLocation.artifactLocation.uri` | 源文件路径，**建议用仓内相对路径**（绝对路径也支持） |
| `locations[0].physicalLocation.region.startLine` | 行号，点击跳转用 |
| `partialFingerprints.findingIndex` | 告警稳定标识（见下） |
| `properties.confidence` / `severity` / `ruling` | 详情面板展示（可选） |

### 2.4 findingIndex 约定（标注闭环的前提）

`findingIndex` 是告警的唯一标识，标注回传靠它在文件中回查告警。

- **强烈建议**产出管道为每条 result 注入稳定的 `partialFingerprints.findingIndex`
  （例如 `ruleId + uri + line + 代码片段哈希`），保证同一条告警在多轮评审间标识不变。
- 若缺失，扩展与 `scripts/_lib.py` 使用一致的 fallback：
  `ruleId/uri:startLine`（如 `cwe-476/src/x.c:5`）。此时标注链路仍可工作，
  但代码行移动会导致标识漂移。

## 3. 日常使用

1. 用 VS Code 打开被审代码仓，确保告警文件（`.sarif` / `.jsonl`）已放在仓内
   （例如 CI 下载到 `.review/` 目录）。
2. 点击活动栏 **AI Reviewer** 图标，Findings 视图按 **文件 → 规则 → 告警** 分组展示。
3. 点击告警打开详情面板：规则、位置（点击跳转源码行）、完整消息、置信度、结论。
4. 标注：树节点上的 👍/👎 内联按钮，或详情面板按钮，或命令面板
   `Mark as True/False Positive`：
   - 👍 TP → 生成 incident_pattern 提案进 quarantine；
   - 👎 FP → 该规则 violations+1，30 天内满 3 次触发场景改进提案。
5. 视图标题栏的刷新按钮可手动重扫。

## 4. 在企业 C/C++ 仓上部署

**只看不标**：零依赖。只要告警文件放进仓内即可浏览、跳转，扩展不解析代码，
对语言无感。clang-tidy / cppcheck / CodeQL 的原生 SARIF 均可直接使用
（无 `findingIndex` 时走 fallback）。

**标注回传**：依赖一份 agent-reviewer 仓库（含 `scripts/memory-label.sh`、
`.venv`、`memory/team.db`）。两种方式：

- 直接把 agent-reviewer 仓作为 VS Code 工作区打开（开发/试用）；
- 在被审仓的设置中把 `agentReviewer.reviewerRoot` 指向该仓在本机的路径
  （企业内可统一部署一份到固定路径）。

找不到标注后端时扩展 fail-open：浏览功能不受影响，点标注仅弹警告。

**已知限制**：源码跳转基于第一个 workspace folder 解析相对路径，
多 root 工作区下其他 root 的文件可能跳转失败；单仓使用无影响。

## 5. 设置项

| 设置 | 类型 | 默认 | 说明 |
|---|---|---|---|
| `agentReviewer.reviewerRoot` | string | `""` | agent-reviewer 仓库路径（含 `scripts/memory-label.sh`）。空 = 尝试工作区根。 |
| `agentReviewer.autoLoad` | boolean | `true` | 启动时自动加载工作区所有告警文件。 |
| `agentReviewer.showLabeled` | boolean | `false` | 显示本次会话中已标注的告警。 |

## 6. 故障排查

- **视图是空的**：确认告警文件扩展名为 `.sarif`/`.jsonl` 且不在 `node_modules` 下；
  JSON 语法错误会导致整个文件被跳过（其他文件不受影响）。
- **标注报"找不到 memory-label.sh"**：设置 `agentReviewer.reviewerRoot`。
- **标注报"不在 xxx 中"**：告警缺少 `partialFingerprints.findingIndex` 且行号已移动，
  fallback 标识对不上；重新生成告警文件或注入稳定 findingIndex。
