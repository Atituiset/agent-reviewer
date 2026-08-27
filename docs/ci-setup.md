# CI 安装说明：给目标仓接入 ai-review

## 快速安装

```bash
# 在目标仓根目录（以 AetherStack 为例）
mkdir -p .github/workflows
cp /path/to/agent-reviewer/ci/ai-review.yml .github/workflows/ai-review.yml
```

目标仓的 caller 只有 10 行，评审逻辑集中在 `Atituiset/agent-reviewer` 的[可复用 workflow](../.github/workflows/ai-review-reusable.yml)——**场景库与评审逻辑更新时目标仓零改动**。

## 配置：secrets 与 vars

| 名称 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `AI_REVIEW_API_KEY` | Secret | 是 | 模型 API key（Anthropic 或 DeepSeek 或其他 Anthropic 兼容端点的 key） |
| `AI_REVIEW_BASE_URL` | Variable | 否 | 留空 = Anthropic 直连；DeepSeek 填 `https://api.deepseek.com/anthropic`；其他兼容端点同理（Z.ai / MiniMax / Kimi / OpenRouter…） |
| `AI_REVIEW_MODEL` | Variable | 否 | 模型 ID，如 `deepseek-chat`、`deepseek-reasoner`；留空用 action 默认 |

**用 DeepSeek 的最小配置**：secret `AI_REVIEW_API_KEY` = DeepSeek key；variable `AI_REVIEW_BASE_URL` = `https://api.deepseek.com/anthropic`；variable `AI_REVIEW_MODEL` = `deepseek-chat`（依据：[DeepSeek 官方 Anthropic 兼容 API](https://api-docs.deepseek.com/guides/anthropic_api)）。

`GITHUB_TOKEN` 由 Actions 自动提供；code scanning 需要 public 仓库或 GitHub Advanced Security。

## 行为约定

- **触发**：PR opened / synchronize
- **豁免**：diff 增删行 <20，或仅触及 `.md/.txt/docs/`——跳过评审
- **fail-open**：评审步骤（模型调用）失败不阻塞 PR，仅日志留痕；SARIF 只在评审成功时上传
- **输出**：findings 出现在 PR 的 Checks → code scanning（category: agent-reviewer）

## 注意

- CI 侧只做「评审 + 展示」，**不接团队记忆库**；记忆飞轮只发生在本地（VSCode 扩展 + memory-label.sh）
- caller 中 `@mvp` 是可复用 workflow 的分支引用，合入主干后改为 `@main`；需要可复现性时钉 tag（如 `@v0.1.0`）
- 模型成本：仅在有实质代码变更的 PR 上运行；可在 prompt 中限制评审范围（如只审 `stack/`）
