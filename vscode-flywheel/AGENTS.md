# AGENTS.md — Agent Reviewer Flywheel 开发约束

本文件面向在本仓库上进行定制开发的 AI Agent 与工程师。**改代码前先读完本文件。**

## 项目概述

VS Code 扩展：扫描工作区内的告警文件（`*.sarif` / `*.jsonl`），在树视图中浏览，
并把人工标注（真/假阳性）通过本地脚本回传给记忆飞轮。无 HTTP 服务、无运行时依赖
（仅 VS Code API + Node 内置 `fs`/`path`/`child_process`）。

## 目录结构

```
src/extension.ts    入口：命令注册、工作区扫描（findFiles）、watcher 装配
src/sarifLoader.ts  告警文件解析（.sarif 整文件 / .jsonl 逐行）+ SarifStore
src/fileWatcher.ts  文件监听（createFileSystemWatcher）
src/treeProvider.ts Findings 树视图（文件 → 规则 → 告警）
src/findingPanel.ts 告警详情 WebView + 跳转源码
src/labelClient.ts  标注回传：调用外部 memory-label.sh，fail-open
out/                tsc 产物（gitignored；勿手改，F5 或打包前先 npm run compile）
```

## 构建与验证

```bash
npm install            # 需要 @types/node、@types/vscode、typescript（devDependencies）
npm run compile        # tsc -p ./，strict 模式，必须通过
npm run watch          # 增量编译
npx @vscode/vsce package   # 产出 *.vsix
```

- 按 **F5** 启动 Extension Development Host 做人工验证。
- 本仓无自动化测试；改动解析/标注逻辑后，至少用夹具文件（一 `.sarif` + 一
  `.jsonl`）在 Development Host 里验证：加载数量正确、详情可打开、跳转正确。

## 硬约束

1. **findingIndex fallback 必须与标注后端逐字符一致。**
   `sarifLoader.ts` 的 `fallbackFindingIndex()` 与标注后端的回查逻辑计算同一字符串
   （当前为 `ruleId/uri:startLine`）。任何一端改动必须同步另一端，否则标注回传静默失败
   （报"不在 xxx 中"）。后端当前在外部仓库 agent-reviewer 的 `scripts/_lib.py`
   （`_fallback_finding_index`）；独立建仓后需决定后端归属（见"外部依赖"）。

2. **文件发现 glob 有两处，必须同步改**：`extension.ts` 的 `findFiles` 和
   `fileWatcher.ts` 的 `createFileSystemWatcher`（当前均为 `**/*.{sarif,jsonl}`）。
   新增格式的解析分支在 `sarifLoader.ts` 的 `loadSarifFile()`。

3. **标注链路 fail-open**：`labelFinding()` 永不抛异常，所有失败走
   `showWarningMessage`。浏览功能不得因标注后端缺失/损坏而受影响。

4. **标注后端接口契约**（改后端时必须保持）：
   `bash memory-label.sh <file-path> <findingIndex> <tp|fp> [reason]`，
   stdout 输出单行 JSON：`{"ok": true, ...}` 或 `{"ok": false, "code", "message"}`，
   FP 时可带 `fp_count`。非零退出或 `ok !== true` 视为失败。
   后端查找顺序：`agentReviewer.reviewerRoot` 配置 → 各 workspace folder 下的
   `scripts/memory-label.sh`。

5. **源码跳转基于 `workspaceFolders[0]`** 解析相对路径（`findingPanel.ts`）。
   多 root 支持是有意的遗留限制，改动前确认需求。

6. **TypeScript strict 模式**：`commonjs` / `es2020`，不放宽 tsconfig；
   不引入新的运行时依赖（确需引入时先在 PR/提交说明中写明理由）。

7. **文档同步**：改动行为、格式约定、设置项时，同提交更新 `README.md`（英文）与
   `USAGE.md`（中文使用文档）。

## 外部依赖（独立建仓后必须处理）

- 标注后端（`memory-label.sh` 及其 Python 实现、记忆库）不在本仓。企业内独立部署时
  三选一：随仓分发脚本、统一部署到固定路径用 `reviewerRoot` 指向、或改造
  `labelClient.ts` 为 HTTP 上报。选择后更新本文件与 USAGE.md。
- `package.json` 的 `repository` 字段当前指向上游 agent-reviewer 仓，
  独立建仓后改为内网仓地址（vsce 打包要用它解析 README 相对链接）。
- `node_modules` 不入库；内网构建需可用的 npm registry 镜像或离线缓存。

## 提交规范

- 提交信息遵循上游风格：`领域: 中文描述`（如 `sarifLoader: 支持 jsonl 逐行解析`）。
- 构建产物（`out/`、`*.vsix`）不入库，`out/` 已 gitignore；VSIX 通过 Release 分发。
