# review-gate hook 安装与运维

## 安装（Claude Code 宿主）

项目 `.claude/settings.json` 增加：

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [{ "type": "command", "command": "$CLAUDE_PROJECT_DIR/hooks/pre-commit-gate.sh" }]
      }
    ]
  }
}
```

其它宿主：把 `pre-commit-gate.sh` 挂到等价「命令执行前」钩子即可；脚本本身只依赖 bash + git + python。

## 会话隔离

工件路径 `.git/review-gate/<session-id>.json`（session id 取自 hook stdin），并行会话互不覆盖；无 session 上下文时回退 `.review/last-review.json`。

## 运维开关

- **临时停用**：`mkdir -p .review && touch .review/DISABLED`（kill switch，放行留痕进 metrics）
- **豁免规则**：diff < 20 行、纯文档（`*.md` / `docs/**`）自动放行
- **熔断出口**：评审残留问题走 ESCALATED 工件（escalated:true + 逐条 ruling），放行但留痕

## deny 稳定码集（oss-reuse §6 移植）

| 码 | 含义 |
|---|---|
| E_NO_ARTIFACT | 无评审工件 |
| E_PARTIAL_STAGE | 存在 unstaged 改动（须完整暂存） |
| E_HASH_MISMATCH | 评审后代码已变动，hash 失配 |
| E_VERDICT | verdict 三态校验不过 |
| E_STALE | 工件超 24h |
| E_UNKNOWN_SCENARIO | finding 引用了不存在的场景键 |
| E_MALFORMED / E_GIT | 工件结构损坏 / git 异常 |

所有拦截/放行均 append 到 `.review/metrics.jsonl`（MVP 设计 §4）。
