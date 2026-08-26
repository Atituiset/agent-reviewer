# MVP 目标仓验证手册（手动执行版）

> 用途：在任意真实 git 仓库上端到端验证 MVP 组件链（门禁 → 打包 → 评审 → 工件三态 → 记忆治理）。
> 每步给出「命令 → 期望输出 → 勾选项」，人工逐条 check。
> 已跑通记录：[trial-u-boot.md](trial-u-boot.md)。本手册参数已预填 **AetherStack**。

## 0. 前置与变量

```bash
# 本仓（MVP 组件所在，mvp 分支）
export R=/home/atituiset/Projects/agent-viewer-research
# 目标仓（本次验证对象）
export TARGET=/home/atituiset/Projects/AetherStack
export SESSION=trial-$(date +%s)          # 会话 id，防并行覆盖工件
cd "$R" && ./scripts/setup-env.sh          # 首次一次：建 .venv
```

目标仓要求：工作区干净、有 ≥1 个提交。**不要**在 master 上直接做试验：

```bash
git -C "$TARGET" checkout -b trial/review-gate
```

## T0 门禁拦截（无工件必须被拒）

对目标仓做一次 **≥20 行的非纯文档改动**（真实变更或播种已知缺陷模式），并完整暂存：

```bash
$EDITOR "$TARGET/<某个 .cc 或 .c 文件>"    # 改动 ≥20 行；播种建议见附录 A
git -C "$TARGET" add -A
printf '{"session_id":"%s","tool_input":{"command":"git commit -m t"}}' "$SESSION" \
  | MVP_ROOT="$TARGET" bash "$R/hooks/pre-commit-gate.sh"; echo "rc=$?"
```

- [ ] rc = **2**
- [ ] 输出含 `E_NO_ARTIFACT`（未 stage 完整时还会带 `E_PARTIAL_STAGE`——属正确行为）
- [ ] deny reason 带修正提示（运行 /sdd-review）

> 反向抽查豁免：<20 行改动或仅 `*.md`/`docs/**` 时应 rc=0 放行。

## T1 打包评审输入

```bash
bash "$R/scripts/review-package.sh" --out "/tmp/review-$SESSION"
cat "/tmp/review-$SESSION/scenarios.json"
head -30 "/tmp/review-$SESSION/context.md"
```

- [ ] `scenarios.json` 命中的场景与改动文件类型相符（C/C++ → 内存安全簇 + default）
- [ ] context.md 三节齐全：变更文件清单 / 命中场景索引 / 记忆召回（首跑为空属正常）

## T2 派发评审（人工决策点，二选一）

- **方式 A（推荐）**：在 Claude Code 中于目标仓内运行 `/sdd-review` 命令体，
  controller 自动打包、派发 task-reviewer subagent 并落盘工件。
- **方式 B（完全手动）**：把 `/tmp/review-$SESSION/` 交给任一 fresh-context agent
  （或同事），契约文件是 `$R/agents/task-reviewer.md`，要求按其输出契约返回工件 JSON。

拿到 findings 后人工逐条处置：修复 / dispute 并写 ruling。

## T3 工件三态生命周期校验

先写 **ISSUES_FOUND 版**（把评审返回 JSON 存为文件，字段 diff_hash/reviewed_at 可用下面命令补）：

```bash
HASH=$(git -C "$TARGET" diff HEAD | sha256sum | cut -d' ' -f1)
mkdir -p "$TARGET/.git/review-gate"
$EDITOR "$TARGET/.git/review-gate/$SESSION.json"   # 粘贴工件；diff_hash=$HASH，reviewed_at=当前 UTC ISO
MVP_ROOT="$TARGET" bash "$R/scripts/verify-artifact.sh" --session "$SESSION"; echo "rc=$?"
```

- [ ] ISSUES_FOUND 且存在未解决 finding → rc = **2**，码 `E_VERDICT`

改判 **ESCALATED**（escalated=true，每条残留 finding 补人工 ruling）后再验：

```bash
$EDITOR "$TARGET/.git/review-gate/$SESSION.json"
MVP_ROOT="$TARGET" bash "$R/scripts/verify-artifact.sh" --session "$SESSION"; echo "rc=$?"
printf '{"session_id":"%s","tool_input":{"command":"git commit -m t"}}' "$SESSION" \
  | MVP_ROOT="$TARGET" bash "$R/hooks/pre-commit-gate.sh"; echo "gate_rc=$?"
```

- [ ] ESCALATED 带 ruling → verify rc=**0**，gate rc=**0** 放行
- [ ] hash 绑定抽查：放行后对目标仓再改任意已跟踪文件并 `git add`，重跑 gate 应 rc=2 `E_HASH_MISMATCH`

## T4 记忆链路（propose → approve → recall）

```bash
# 4a 无证据拒收
echo '{"content":"无证据条目"}' | MVP_ROOT="$TARGET" bash "$R/scripts/memory-propose.sh"; echo "rc=$?"      # 期望 rc=2 E_NO_EVIDENCE
# 4b 正常提案（content 必须含 file:line）
echo '{"content":"模式一句话 (path/to.c:42)","modules":["stack/**"],"bound_paths":["path/to.c"],"evidence":{"review_artifact":"'"${HASH:0:8}"'"}}' \
  | MVP_ROOT="$TARGET" bash "$R/scripts/memory-propose.sh"
ID=$(MVP_ROOT="$TARGET" python3 -c "import os,sys;sys.path.insert(0,'$R/scripts');import _lib as l;print(l.db().execute(\"select id from memories where status='quarantine'\").fetchone()[0])")
# 4c 未审核不可见
MVP_ROOT="$TARGET" bash "$R/scripts/memory-recall.sh" path/to.c            # 期望空
# 4d 审核 → 召回
MVP_ROOT="$TARGET" bash "$R/scripts/memory-approve.sh" "$ID"
MVP_ROOT="$TARGET" bash "$R/scripts/memory-recall.sh" path/to.c            # 期望出现该条
MVP_ROOT="$TARGET" bash "$R/scripts/memory-recall.sh" unrelated/x.py       # 期望空
```

- [ ] 4a rc=2；4b 返回 quarantine id
- [ ] 4c 空、4d 目标路径可见且不相关路径为空（GLOB 召回语义正确）

## T5 metrics 全程留痕

```bash
tail -6 "$TARGET/.review/metrics.jsonl"
```

- [ ] 能看到完整的 deny→deny→allow 轨迹及 reason/codes

## 归档（T6，推荐：让试验可从本仓一路点回源码）

```bash
# 1) 播种改动提交成远端分支（记录永久可追溯；分支标勿合并）
git -C "$TARGET" commit -m "trial(review-gate): 播种缺陷试验件——勿合并"
git -C "$TARGET" push -u origin trial/review-gate

# 2) 证据卷入 MVP 仓 trials/<会话id>/
E="$R/trials/$SESSION" && mkdir -p "$E"
cp "/tmp/review-$SESSION/"{diff.patch,context.md,scenarios.json} "$E/"
cp "$TARGET/.git/review-gate/$SESSION.json" "$E/review-artifact.json"
cp "$TARGET/.review/metrics.jsonl" "$E/"
# 3) 写 $E/README.md：出处表 + 远端分支/commit 直链 + diff_hash 复核命令
```

- [ ] `sha256sum "$E/diff.patch"` 与工件 `diff_hash` 一致
- [ ] README 含 GitHub 分支与 commit 直链，从本仓可一键跳转

## 清理（验证完成后恢复目标仓）

```bash
git -C "$TARGET" checkout master && git -C "$TARGET" branch -D trial/review-gate
rm -rf "$TARGET/memory" "$TARGET/.review" "$TARGET/.git/review-gate"
git -C "$TARGET" status --short        # 期望干净
```

---

## 附录 A：播种缺陷模式参考（对照场景 checklist 的检测信号）

| 场景 | 最小可播种片段 |
|---|---|
| cwe-476 | `p = malloc(n); memcpy(p, src, n);`（无判空） |
| cwe-787 | `char buf[32]; strcpy(buf, in);`（in 为无约束参数） |
| cwe-401 | 提前 return 分支漏 free/fclose |
| cwe-416 | free 后同指针再解引用一次 |

播种目的＝已知真值的检出实验（golden 局部版）；**务必走完清理节还原目标仓**。
批量度量请等团队 cases 迁入 `rules/scenarios/*/cases/` 后跑回放基线（MVP 设计 §2.4.2）。
