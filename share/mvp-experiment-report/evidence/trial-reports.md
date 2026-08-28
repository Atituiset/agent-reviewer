# 试验报告汇编（脱敏版）


---

<!-- 来源: trials/uboot-trial-001/REVIEW.md -->

# 检视报告 · uboot-trial-001

> 被审变更：`common/cli.c` 新增 `cli_build_banner()`（+19 行，[diff.patch](diff.patch)）
> 评审方：task-reviewer（fresh-context subagent）· 日期：2026-08-26
> **结论：ESCALATED —— 3 条 finding（2 important / 1 minor），逐条 ruling 后放行（试验分支，不合并）**
> 机器可读工件：[review-artifact.json](review-artifact.json) · diff_hash `7e7b6ad4…c582`

## 评审范围

- 场景：cwe-787、cwe-476、cwe-125、cwe-401、cwe-416、cwe-190、default（7 个）
- spec_ref：无（试验件无对应 spec）

## Findings

### ① important · security · cwe-787 —— 无界 strcpy 进栈缓冲（置信度 95%）

**位置**：`common/cli.c:361`

`cli_build_banner()` 执行 `strcpy(scratch, board)`，其中 `scratch` 为 `char[32]` 栈缓冲。`board` 长度无任何约束，≥32 字节的输入即摧毁栈帧。

**证据**：refs CWE-787 / CWE-120；函数内无任何长度校验点。

**修复建议**：去掉 scratch 中转，直接 `snprintf(banner, size, "%s#", board)`。

**ruling**：播种缺陷（试验件），分支用后即焚，不合并。

### ② important · bug · cwe-476 —— malloc 返回值未判空直传 snprintf（置信度 92%）

**位置**：`common/cli.c:362`

`banner = malloc(CLI_BANNER_BUF)` 后未判空即作为 `snprintf` 写入目标。分配失败时写入地址 0。

**证据**：上游 `lib/vsprintf.c:583-585` 的 `vsnprintf_internal` 无 NULL 保护；且树内惯例要求判空（`run_command_list()`，cli.c:141-143）。

**修复建议**：判空并在失败时返回 NULL。

**ruling**：播种缺陷（试验件），不合并。

### ③ minor · bug · MISSING_IMPL —— 新导出函数无原型、全树零调用（置信度 85%）

**位置**：`common/cli.c:356`

`cli_build_banner()` 未在 `include/cli.h` 声明原型，且全树无任何调用方——导出即死代码，集成缺口。

**ruling**：评审判断正确（真实增量发现，非播种）；随分支回滚自然消解。

## 评审质量注记

- 行级锚点全部精确；finding ② 给出了跨文件上游证据链与树内惯例佐证
- 无风格类噪音；verdict 诚实报 ISSUES_FOUND 而非凑数 CLEAN
- 处置：T3a（未解决 finding 工件过闸）正确拒绝 → T3b（ESCALATED + 逐条 ruling）放行，门禁机械行为符合设计


---

<!-- 来源: trials/uboot-trial-002/REVIEW.md -->

# 检视报告 · uboot-trial-002（SKILL 格式转换后回归评审）

> 被审变更：`common/cli.c` 新增 `cli_build_banner()`（+19 行，[diff.patch](diff.patch)）
> 评审方：task-reviewer · 日期：2026-08-27
> **清单来源：转换后的 `rules/scenarios/*/SKILL.md`**（每条 finding 标注命中的清单条目）
> **结论：ISSUES_FOUND —— 3 条 finding（2 important / 1 minor），与格式转换前 uboot-trial-001 的评审结果完全一致**
> 机器可读工件：[review-artifact.json](review-artifact.json) · diff_hash `7e7b6ad4…c582`（与 trial-001 同 diff）

## 评审范围

- 场景（确定性路由，11 个）：cwe-125、cwe-190、cwe-20、cwe-362、cwe-401、cwe-416、cwe-476、cwe-78、cwe-787、cwe-798、default
- spec_ref：无（试验件无对应 spec）

## Findings

### ① important · security · cwe-787 —— 无界 strcpy 进栈缓冲（置信度 95%）

**位置**：`common/cli.c:361`

`strcpy(scratch, board)`，`scratch` 为 `char[32]` 栈缓冲，`board` 长度无约束，≥32 字节即摧毁栈帧。

**命中清单条目**：`cwe-787/SKILL.md` 检测信号 #1「memcpy/strcpy/sprintf 族目标缓冲区大小与源长度未核对」。

**修复建议**：去掉 scratch 中转，直接 `snprintf(banner, size, "%s#", board)`。

**ruling**：播种缺陷（试验件），不合并。

### ② important · bug · cwe-476 —— malloc 返回值未判空直传 snprintf（置信度 92%）

**位置**：`common/cli.c:362`

`malloc` 返回值未判空即作为 `snprintf` 写入目标；分配失败时写地址 0（上游 `lib/vsprintf.c:583-585` 的 `vsnprintf_internal` 无 NULL 保护；树内惯例见 cli.c:141-143）。

**命中清单条目**：`cwe-476/SKILL.md` 检测信号 #1「malloc/calloc/new 及各类 find/get/lookup 返回值未判空即解引用」。

**ruling**：播种缺陷（试验件），不合并。

### ③ minor · bug · MISSING_IMPL —— 新导出函数无原型、全树零调用（置信度 85%）

**位置**：`common/cli.c:356`

未在 `include/cli.h` 声明原型且全树无调用方，导出即死代码。

**命中清单条目**：`default/SKILL.md`「变更面：是否有死代码被引入」。

**ruling**：评审判断正确（真实增量发现，非播种）；随分支回滚自然消解。

## 与 trial-001 的对照（格式转换回归结论）

| 维度 | trial-001（旧 checklist 格式） | trial-002（SKILL 格式） | 结论 |
|---|---|---|---|
| finding 数 | 3 | 3 | 一致 |
| 播种缺陷命中 | 2/2（cwe-787、cwe-476） | 2/2 | 一致 |
| 行级锚点 | 361 / 362 / 356 | 361 / 362 / 356 | 一致 |
| 真实增量发现 | MISSING_IMPL ×1 | MISSING_IMPL ×1 | 一致 |
| 场景路由数 | 8 + default（旧 registry） | 11（新 registry，并集语义含 cwe-20/78/798） | 见注 |

注：路由数差异来自新格式下 cwe-20/cwe-78/cwe-798 按 languages 正确命中 C 文件（并集语义的预期行为），其中 cwe-78 对本文件为噪音（二级收敛候选，见 docs/validation 报告遗留项 1）。

**结论：场景库 SKILL 格式转换后，端到端评审结果与转换前完全一致——格式迁移无功能回归。**


---

<!-- 来源: trials/aether-trial-001/REVIEW.md -->

# 检视报告 · aether-trial-001

> 被审变更：`stack/nas/src/nas_messages.cpp` 追加 `make_padding_frame()`（+22 行，[diff.patch](diff.patch)）
> 评审方：task-reviewer（fresh-context subagent）· 日期：2026-08-26
> **结论：ESCALATED —— 5 条 finding（1 critical / 4 important），逐条 ruling 后放行（试验分支，不合并）**
> 机器可读工件：[review-artifact.json](review-artifact.json) · diff_hash `ad5ea812…7618`

## 评审范围

- 场景：cwe-125、cwe-190、cwe-362、cwe-401、cwe-416、cwe-476、cwe-78、cwe-787、default（9 个）
- spec_ref：无（试验件无对应 spec）

## Findings

### ① critical · bug · default —— decode 缺收尾大括号，翻译单元无法编译（置信度 98%）

**位置**：`stack/nas/src/nas_messages.cpp:29`

`make_padding_frame` 被嵌套定义在 `NasMessage::decode` 函数体内——`decode` 的闭合括号缺失。

**证据**：`g++ -fsyntax-only` 复现 `function-definition is not allowed here`（编译器实证，非推测）。

**ruling**：播种 Edit 误吞闭合括号——真实缺陷确认；分支用后即焚。

### ② important · security · cwe-401 —— early-return 路径内存泄漏（置信度 96%）

**位置**：`stack/nas/src/nas_messages.cpp:35`

tag 为空的 early-return 路径未 `free(frame)`：`malloc` 于 L32-33，唯一释放点在 L44，提前返回绕过释放。

**ruling**：播种缺陷（cwe-401，验证检出率用）。

### ③ important · security · cwe-401 —— 第二条泄漏路径（置信度 96%）

**位置**：`stack/nas/src/nas_messages.cpp:38`

body 超限的 early-return 同样泄漏：超限校验发生在 `malloc` **之后**，与 ② 同型。

**ruling**：播种缺陷（cwe-401 第二路径）。

### ④ important · security · cwe-476 —— malloc 未判空即作 memcpy 写入目标（置信度 84%）

**位置**：`stack/nas/src/nas_messages.cpp:33`

分配失败时 L40 对空指针写入，未定义行为。

**ruling**：播种缺陷（cwe-476）。

### ⑤ important · conformance · EXTRA_IMPL —— 试验脚手架落入产品源文件（置信度 88%）

**位置**：`stack/nas/src/nas_messages.cpp:27`

新增函数在头文件无声明、全仓零调用（diff 中 `TRIAL SEED` 注释自述）；`spec_ref=none` 本身有 AMBIGUOUS 风险。

**ruling**：对种子本身的元发现正确；分支将删除。

## 评审质量注记

- 检出 3 类播种缺陷（cwe-401 ×2 路径、cwe-476）外，**额外捕获播种操作本身引入的编译级真实缺陷**（①）——critical 级，且以编译器复现为证据而非推测
- finding ②③ 区分了两条同型泄漏路径并分别锚定行号，未合并含糊处理
- 门禁轨迹（metrics.jsonl）：豁免放行（19 行）→ deny(NO_ARTIFACT)×2 → allow(artifact-ok)，机械行为符合设计


---

<!-- 来源: trials/aether-trial-002/REVIEW.md -->

# 检视报告 · aether-trial-002（AetherStack M16-M22 真实新代码）

> 被审变更：commit `8394245`（M16-M22：多 UE U2U、SIP 呼叫、QoS 承载、链路自适应、RRC Inactive、5G-AKA、双 BS 切换）的 `stack/` C++ 改动——52 文件，+6929/-531（[diff.patch](diff.patch)，368 KB）
> 评审方：5 个并行场景评审 subagent（fresh context）+ 主控逐条核实 · 日期：2026-08-27
> **结论：ISSUES_FOUND —— 4 条 finding（3 important / 1 minor），全部为真实新代码缺陷（非播种）**
> 机器可读工件：[review-artifact.json](review-artifact.json) · diff_hash `6485c5bd…d170`

## 评审范围与方法

- **确定性路由**：52 个变更 C/C++ 文件全部命中 C 系场景集（cwe-125/190/20/362/401/416/476/78/787/798 + default），27 个 cpp/hpp 追加 cwe-22（[routing.txt](routing.txt)、[changed-files.txt](changed-files.txt)）
- **抽样评审**：按风险选 5 个文件——新文件 `u2u.cpp`（输入解析）、`aka.cpp`（认证向量）、改动高危区 `frame.cpp`（容量变更）、`rlc_um.cpp`（序号/定时器）、`bs_node.cpp`（+890 行，切换/调度）
- **双段验证**：subagent 产出候选 → 主控逐条读码核实（4 条候选全部复核成立；1 条边界情形因无法构造 ≥80 置信度路径被正确丢弃；1 条 diff 外遗留问题按纪律排除）

## Findings

### ① important · security · cwe-125 —— XN_HO_PREPARE 长度校验 off-by-one 越界读（置信度 95%）

**位置**：`stack/core/src/bs_node.cpp:1082`

报文格式 `{tmsi:4}{from:2}{to:2}{sec:1}{key:32}{imsi_len:1}` 至少 **42** 字节，守卫却写 `if (msg.value.size() < 41) break;`。恰好 41 字节时 `msg.value[41]`（读 imsi_len）越界。Xn 报文来自网络对端，属外部输入路径。

**修复**：守卫改为 `< 42`。

### ② important · bug · cwe-190 —— RLC UM reorder 超时在 SN 回绕时选错恢复点（置信度 90%）

**位置**：`stack/rlc/src/rlc_um.cpp:134`

`ahead()` 按 `int16_t` 模运算接纳乱序包（`vr_next_=65530` 时 65531 和 2 都是合法缓存），但超时恢复 `resume = buffer_.begin()->first` 取 `std::map` **数值**最小键——回绕后选到 2 而非序列上更靠前的 65531：交付顺序反转、`dropped_` 虚增（二次超时可达 ~65528）、`vr_next_` 模意义倒退。

**修复**：按模序列空间选最靠前键（从 `vr_next_` 起扫描，或用序列比较器排序）。

### ③ important · bug · cwe-401 —— 切换失败路径状态泄漏 + 新 guard 永久阻断 UE 切换（置信度 85%）

**位置**：`stack/core/src/bs_node.cpp:1274`

`initiated_ho_`/`pending_xn_ho_` 的 erase 只在成功路径（868/1104/1127）；detach 只清 `tmsi_to_crnti_`/`flows_`，无超时无回滚。更关键的是本 diff **新引入**的 in-flight 早退 `if (initiated_ho_.count(crnti)) return;`——HO_COMMAND 经有损空口丢失（本仿真演示的正是 dark/lossy 小区）后，残留条目使该 UE 所有后续 meas report 不再触发切换：**UE 永久钉死在变差的小区**。

**修复**：失败/超时路径清理两个 map；guard 增加时效或次数判断。

### ④ minor · bug · cwe-401 —— ho_prepared_ 任何路径不释放（置信度 88%）

**位置**：`stack/core/src/bs_node.cpp:1361`

`prepare_handover` 写入 `ho_prepared_[new_crnti]`（含 32 字节 UP 密钥与 IMSI），全库无对应 erase：每次切入永久泄漏一份 HoContext；UE 永不到达时连带泄漏 flow/RRC/NAS 上下文和 tmsi→crnti 幻影映射。

**修复**：HO_COMPLETE 消费后 erase；准备超时回收。

## 阴性记录（precision 证据）

| 文件 | 结果 |
|---|---|
| `stack/app/src/u2u.cpp`（新，SIP 解析） | 零 finding：每步读取有前置长度校验、字段白名单齐全、全托管内存—— reviewer 给出逐条边界推演 |
| `stack/nas/src/aka.cpp`（新，5G-AKA） | 零 finding：定长数组操作无越界路径、无硬编码密钥；两处 3GPP 偏差被正确判定为「模拟器设计范畴」不上报 |
| `stack/phy/src/frame.cpp`（容量变更） | 零 finding（本 diff 范围）；评审注意到 frame.cpp:190 附近一处**本 diff 未触及**的潜在越界读，按「仅报本次改动」纪律正确排除——留给全量扫描场景 |

## 试验结论

- **检出**：4 条真实缺陷（1 边界越界读、1 序号回绕逻辑、2 资源/状态管理），均经主控读码复核成立
- **精度信号**：3 个干净文件零误报；2 条不达标候选被纪律正确过滤（1 条无法构造路径、1 条 diff 外）——「并行评审 + 二次核实」的双段机制按设计工作
- **流程**：确定性路由（52 文件秒级）→ 风险抽样 → 并行场景评审 → 主控核实 → 工件 + 人读报告，全链路留痕
- 处置建议：4 条 finding 转 AetherStack 团队 triage（ruling: pending-team-triage）；①② 建议修复，③④ 建议补超时回收逻辑


---

<!-- 来源: trials/aether-trial-003/README.md -->

# 试验证据卷 · aether-trial-003：三模式对比 + FP 对照（2026-08-28）

> 目标：在 GitHub CI 上验证三种评审形态（模式 1 纯场景库 / 模式 2 +codegraph / 模式 3 +navmap），
> 并用「入口判空 → 函数指针表分发 → 深处解引用」试验件复现核心仓的系统性 FP 场景。
> 试验仓 AetherStack，试验分支 `trial/mode-*`、`trial/mode-fp-tbl-*`（均不合并）。

## 一、PR 与运行清单

| PR | 分支 | 模式 | run | 结论 |
|---|---|---|---|---|
| [#2](<仓库地址略>) | trial/mode-1 | 1 | 33139101947 | success |
| [#3](<仓库地址略>) | trial/mode-2 | 2 | 33139104063 | success |
| [#4](<仓库地址略>) | trial/mode-3 | 3 | 33139107235 | success |
| [#7](<仓库地址略>) | trial/mode-fp-tbl-1 | 1 | 33140153365 | success |
| [#8](<仓库地址略>) | trial/mode-fp-tbl-2 | 2 | 33140158109 | success |
| [#9](<仓库地址略>) | trial/mode-fp-tbl-3 | 3 | 33140164450 | success |
| — | navmap-nightly ×2 | — | 33138281072 / 33140177336 | success |

模式选择机制：PR 分支根目录 `.ai-review-mode` 文件（1/2/3），workflow 按模式组装 prompt 并条件执行 codegraph 索引 / navmap 产物注入步骤。

## 二、试验件与结果

### 2.1 试验件 A（`trial/mode-*`）：abort 兜底契约（2 层直连）

`alloc_or_die` 分配处 abort 兜底 → `fill` 跨 2 层解引用。**三个模式均未产生 FP**——契约在代码中显式可见（abort），基线模型无需 codegraph 也能理解。意外收获：试验件无意埋入的真缺陷（`strcpy` 无界进 64 字节）被三个模式全部稳定命中（cwe-787 @184）。

### 2.2 试验件 B（`trial/mode-fp-tbl-*`）：入口判空 → 函数指针表 → 5 层转发 → 深处解引用

核心仓真实场景的微缩复刻：`handle_fp_request`（aka.cpp，入口统一判空）→ `fp_engine_run` → `FP_HANDLER_TBL` 函数指针表 → 4 层纯转发 → `decode_header` 解引用 `req->buf`（全程无重复判空）。

**三个模式给出了三种深度的答案**：

| 模式 | cwe-476（表驱动 FP） | 结论 |
|---|---|---|
| **模式 1** | **报了**（`trial_fp_engine.cpp:24`）——无法跟踪表分发 | ✅ 预期 FP 复现成功 |
| **模式 2** | **未报**——codegraph 链回溯抑制 | ✅ 证伪链路生效 |
| **模式 3** | **报了，但理由质变**：「判空仅存在于 handle_fp_request 单一路径，`fp_engine_run` 是公开入口，直接调用即绕过判空」——不是 FP，是**比 FP 更深一层的真实发现** | ✅ 表感知分析展现出最高分析深度 |

**意外真实缺陷（三个模式全部命中）**：`decode_header` 读 `req->buf[0]` 而入口只判 `buf` 非空未判 `len>0`——零长缓冲区的 1 字节越界读（cwe-125）。非设计播种，属合法检出。

### 2.3 codegraph / navmap 执行证据

- codegraph 实际调用：模式 2 = **29 次**、模式 3 = **16 次**（模式 1 = 0，按设计无索引步骤）
- navmap-nightly 在 `trial/mode-fp-tbl-3` 分支手动触发了产物提取（run 33140177336）

**navmap 暴露的两个真实缺陷**（试验副产品，反馈给 navmap 演进）：

1. **粗筛无 exclude 配置**：候选被 `.navmap-tool/tests/fixtures/`（自身测试夹具）和第三方目录污染，真实源码候选被挤出
2. **分发表模式盲区**：`FP_HANDLER_TBL` 未被提取——裸函数指针数组（无结构体包装）+ `using` 别名形式的函数指针类型不在现有 pattern 内（name_roots 也不含 "tbl"）

## 三、归档工件（本目录）

```
mode-1/ mode-2/ mode-3/                    # 试验件 A 三模式
mode-fp-tbl-1/ mode-fp-tbl-2/ mode-fp-tbl-3/  # 试验件 B 三模式
  ├── run-logs/                # 全部 step 日志（含 codegraph install/sync、prompt 组装、评审、SARIF、upload）
  ├── claude-execution-output.json  # 评审完整轨迹（SDK 消息流，含 codegraph CLI 调用记录）
  └── review.sarif             # 上传 code scanning 的 SARIF 原件（含 codeFlows）
navmap-nightly/
  ├── run-logs/                # nightly 提取全步骤日志
  └── outputs/                 # navmap-outputs 分支产物快照（dispatch/statemachine JSON+md + candidates）
```

## 四、结论

1. **模式 1 的 FP 可以可靠复现**——但前提是契约证据超出模型局部可见范围（函数指针表 + 跨文件），2 层直连 + abort 可见契约在小仓压不住模型
2. **模式 2（codegraph）在表驱动场景能抑制 FP**，模式 3（+navmap）能给出超越 FP 判定的契约级分析——三层能力递进真实存在
3. **规模是差异化的前提**：AetherStack 量级下基线模型大部分情况自足以至模式差异不显著；差异在「表分发 + 跨文件 + 长链」同时出现时才开始显现——这正是千万行级核心仓的常态，spike 结论支持在核心仓按模式 3 形态建设
4. navmap 的两个缺陷（exclude 配置、裸函数指针数组 pattern）建议优先修复，否则在真实仓会被第三方目录与表形态多样性双重稀释
