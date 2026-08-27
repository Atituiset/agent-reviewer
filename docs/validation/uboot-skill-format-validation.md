# u-boot 场景库 SKILL 格式转换回归验证（2026-08-27）

> 背景：场景库由 `checklist.md + meta.yaml` 改造为标准 SKILL.md 格式（`2f7881f`）后，
> 需确认转换未损失路由能力与检测覆盖。验证对象为 `~/Projects/testbeds/u-boot`
> 试验分支 `review-gate-trial@41dd94c8` 的播种缺陷 diff（`common/cli.c`，
> 播种 cwe-787 无界 strcpy + cwe-476 malloc 不判空）。
> 盲测检出能力已于 2026-08-26 的端到端试验证明（见 [trial-u-boot.md](../trial-u-boot.md)，
> 2/2 播种命中 + 1 真实增量发现），本验证只覆盖**格式转换的增量风险**，非重复盲测。

## V1 路由验证（确定性，新 registry）

环境：`scripts/build-registry.sh` 由 14 个 SKILL.md frontmatter 重新生成 `rules/registry.json`（10 条路径规则）。对 `common/cli.c` 匹配结果：

| 项 | 结果 |
|---|---|
| 命中场景数 | **11**：cwe-125、190、362、401、416、476、787（C 系）+ cwe-78（C 系注入类）+ cwe-20、cwe-798（任意语言）+ default |
| cwe-787 在场 | ✅ |
| cwe-476 在场 | ✅ |
| brace glob 解析 | ✅ `**/*.{c,h}` / `**/*.{cc,cpp,hpp}` 正确展开（转换初期曾有大括号被逗号拆开的 bug，已修复并回归） |

与旧格式试验记录（T1：8 个 C 系场景 + default）的差异：cwe-20 / cwe-78 / cwe-798 现在也命中 C 文件——并集语义的正确行为（三者 languages 均含 c/cpp 或任意语言）。其中 **cwe-78（OS 命令注入）对 `cli.c` 这类无命令执行路径的文件是噪音**：每个噪音场景约增加数百 token 的注入成本。建议后续评估按 `origin`/场景元数据做二级收敛（如注入类场景仅在文件含 `system/popen/exec` 等信号时加载），MVP 期接受。

## V2 检测覆盖映射（人工逐条核对）

| 播种缺陷 | 场景清单命中条目 | references 深入项补充 |
|---|---|---|
| ① `strcpy(scratch, board)` 无界拷贝进 `char[32]`（cli.c:361） | cwe-787 SKILL「检测信号」第 1 条：`memcpy/strcpy/sprintf 族目标缓冲区大小与源长度未核对` ✅ | `cwe-787/references/detailed-checks.md`：非受限 API 替换为 snprintf 时的终止符陷阱（`strncpy` 不保证 NUL 结尾） |
| ② `malloc` 返回值直传 snprintf 未判空（cli.c:362） | cwe-476 SKILL「检测信号」第 1 条：`malloc/calloc/new 及各类 find/get/lookup 返回值未判空即解引用` ✅ | `cwe-476/references/detailed-checks.md`：TOCTOU（判空与解引用之间被改写）、智能指针 move 后使用 |

两个播种缺陷均能在**主清单第一条**直接命中，渐进式披露的 references 层提供了修复方向层面的补充——格式转换后「主清单精简 + 深入项按需加载」的结构按预期工作。

## 结论

- SKILL.md 格式转换**无路由损失、无覆盖损失**：14 个场景 frontmatter 全部正确解析，播种缺陷对应的场景与清单条目均在位
- 遗留事项：
  1. cwe-78 类注入场景对纯 C 文件的噪音路由，评估二级收敛策略（不阻塞 MVP）
  2. 检出能力的批量结论仍待 `cases/` 回放基线（`scenario-replay.sh` + 每场景 precision/recall，MVP 设计 §2.4.2）——本次单点验证不构成该结论
  3. AetherStack 的验证待其代码就绪后另行安排
