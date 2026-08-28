# 试验证据卷 · aether-trial-003：三模式对比 + FP 对照（2026-08-28）

> 目标：在 GitHub CI 上验证三种评审形态（模式 1 纯场景库 / 模式 2 +codegraph / 模式 3 +navmap），
> 并用「入口判空 → 函数指针表分发 → 深处解引用」试验件复现核心仓的系统性 FP 场景。
> 试验仓 AetherStack，试验分支 `trial/mode-*`、`trial/mode-fp-tbl-*`（均不合并）。

## 一、PR 与运行清单

| PR | 分支 | 模式 | run | 结论 |
|---|---|---|---|---|
| [#2](https://github.com/Atituiset/AetherStack/pull/2) | trial/mode-1 | 1 | 33139101947 | success |
| [#3](https://github.com/Atituiset/AetherStack/pull/3) | trial/mode-2 | 2 | 33139104063 | success |
| [#4](https://github.com/Atituiset/AetherStack/pull/4) | trial/mode-3 | 3 | 33139107235 | success |
| [#7](https://github.com/Atituiset/AetherStack/pull/7) | trial/mode-fp-tbl-1 | 1 | 33140153365 | success |
| [#8](https://github.com/Atituiset/AetherStack/pull/8) | trial/mode-fp-tbl-2 | 2 | 33140158109 | success |
| [#9](https://github.com/Atituiset/AetherStack/pull/9) | trial/mode-fp-tbl-3 | 3 | 33140164450 | success |
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

---

## 五、闭环续篇：navmap 修复后的模式 3 复审（2026-08-28，`mode-fp-tbl-3-fixed/`）

上一轮结论「数据层面没用上 navmap」的根治记录：

1. **navmap 三处修复**（Atituiset/navmap@`4198745`）：① 粗筛 `exclude_dirs` 配置化 + fnmatch 通配（fixtures/第三方/build-* 不再污染候选，候选 8 → 1）；② name_roots 补 `tbl`；③ 分发表支持**裸函数指针数组**（typedef/using，`msg_id` = 数组下标）。新增 `bare_fnptr` 夹具，测试 42/42
2. **navmap-outputs 更新**（run 33166342331）：`FP_HANDLER_TBL @ trial_fp_engine.cpp:16`（4 项全为 bearer_rx）提取成功，解析失败 0
3. **模式 3 复审**（run 33166873153）：finding 的 reasoning 首次**明确引用两层索引**——

   > 空指针候选（cwe-476）经 **codegraph 链回溯**：fp_engine_run 唯一调用方 handle_fp_request 对同一指针判空；**navmap 分发表 4 项全部解析为 bearer_rx**，判空覆盖完整路径，**故证伪不报**

   真实缺陷（cwe-125，len==0 越界读）保留上报。transcript 中 FP_HANDLER_TBL 提及 42 次、navmap-dispatch-stack 提及 8 次——**「表里有没有、评审引不引」两项验证全部通过**
4. 过程中顺带修复：SARIF `region.startLine` 下限钳制（模型 flow 给 `line:0` 时 upload-sarif 校验失败）

**最终结论**：两层索引从「骨架在位、弹药为空」变成「表里提取得出、评审引用得上」——模式 3 名副其实。
