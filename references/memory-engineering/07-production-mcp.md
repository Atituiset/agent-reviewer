# 07 生产架构与 MCP 互操作

## 7.1 服务 API 形态

生产级记忆服务的典型 API 面：

```
WriteMemory / SearchMemories / ConsolidateMemories / ForgetMemory / GetMemoryStats
```

Memory message 字段：`type / importance_score / created_at / last_accessed_at / related_entity_ids`。

ANDM 扩展（§5.1）：另需两个治理动词——`ReviewMemory`（审核通过/驳回）与 `InvalidateByCommit`（按代码变更失效）——这是 ANDM 区别于通用记忆服务的核心 API 增量。

## 7.2 服务拆分与 Build vs Buy

- Write / Read / Consolidation 三服务拆分，consolidation 异步
- 原则：**「记忆系统的门槛不在基础设施，而在记忆编排层——写入什么、何时 consolidation、怎么融合多信号检索」**。向量库/图库全用托管或现成组件，自研只保留编排层

ANDM 对应（§8）：差异化全在治理规则（quarantine、审核路由、失效引擎），存储底座用现成组件。

## 7.3 MCP Server 形态

Memory 暴露为：

- **tools**：`remember / recall / forget / search`，鉴权 OAuth2；「只暴露可解释动作，注入检测在 server 内」
- **resources**：`memory://<作用域>/<键>` 形式

注意 `requiresConfirmation: true` 模式——高危动作（如根据记忆自动改代码）保留人工确认位。

ANDM 对应（§5.1）：resources 映射为 `memory://module/<path>`（按模块取记忆，正好服务确定性召回）；`propose` 只进 quarantine。

## 7.4 多方写入的冲突解决

参考「LWW + 重要记忆双版本」：普通冲突 Last-Write-Wins，重要条目冲突时**保留双版本而非覆盖**。

ANDM 对应：并发审核冲突时保留双版本（呼应 03 §3.3 的冲突不强行二选一）。

## 7.5 不需要的部分（避免过度设计）

- 端侧实时性约束（P95 <50ms、量化压缩）：ANDM 在服务端、会话开始时注入，延迟预算宽松几个数量级
- 多设备 CRDT/离线同步：ANDM 是中心化服务 + git 式版本化
- 消费级隐私框架（被遗忘权、端云加密分区）：ANDM 需要 RBAC / 审计 / 仓库级隔离
