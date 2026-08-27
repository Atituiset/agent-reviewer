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
