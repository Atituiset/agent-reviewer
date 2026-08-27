# CI 安装说明：给目标仓接入 ai-review

## 快速安装

```bash
# 在目标仓根目录（以 AetherStack 为例）
mkdir -p .github/workflows
cp /path/to/agent-reviewer/ci/ai-review.yml .github/workflows/ai-review.yml
```

## 需要的 secrets

| Secret | 用途 | 备注 |
|---|---|---|
| `ANTHROPIC_API_KEY` | claude-code-action 调模型 | 在目标仓 Settings → Secrets and variables → Actions 配置；也支持 Bedrock/Vertex（改 workflow 中 action 的认证参数，见 anthropics/claude-code-action 文档） |

`GITHUB_TOKEN` 由 Actions 自动提供；`security-events: write` 权限已在模板中声明，用于把 SARIF 上传到 code scanning（仓库需启用 GitHub Advanced Security 或为 public 仓库）。

## 行为约定

- **触发**：PR opened / synchronize
- **豁免**：diff 增删行 <20，或仅触及 `.md/.txt/docs/`——跳过评审
- **fail-open**：评审步骤（模型调用）失败不阻塞 PR，仅在日志留痕；SARIF 只在评审成功时上传
- **输出**：findings 出现在 PR 的 Checks → code scanning（category: agent-reviewer）

## 注意

- CI 侧只做「评审 + 展示」，**不接团队记忆库**（云端无团队记忆）；记忆飞轮只发生在本地（VSCode 扩展 + memory-label.sh）
- 场景库与脚本每次运行时从 `Atituiset/agent-reviewer` 默认分支检出——场景更新即时生效，但如需可复现性，可在 checkout 步骤加 `ref: <tag>` 钉版本
- 模型成本：评审仅在有实质代码变更的 PR 上运行；大 diff 成本与模型选择相关，可在 prompt 中限制范围（如只审 stack/ 目录）
