# 记忆系统工程参考资料（Memory Engineering References）

> 用途：支撑 `docs/design/ai-native-dev-memory-architecture.md` §10 的机制设计。
> 内容说明：本目录是记忆系统工程领域的机制笔记，内容基于公开论文（Generative Agents、Voyager、ExpeL、mem0 等）与工程实践。每条机制标注了其在 ANDM 设计中的对应位置。

## 目录

| 文件 | 主题 | 支撑 ANDM 章节 |
|---|---|---|
| [01 记忆架构与分层](01-architecture.md) | 统一存储、类型标记、生命周期元数据、信任分级 | §4 schema、§10.2 |
| [02 检索 Pipeline](02-retrieval-pipeline.md) | 读写双管线、重要性评分、混合检索、Context Assembly | §5.2、§10.3 |
| [03 生命周期与失效](03-lifecycle.md) | 写入过滤决策树、时间衰减、冲突解决、pinned 保护、蒸馏触发 | §4 状态机、§10.4 |
| [04 压缩与摘要](04-compression.md) | 层级摘要、压缩权衡、记忆蒸馏、原文锚点 | §10.3 |
| [05 评估体系](05-evaluation.md) | 质量指标、安全指标、三级评测法、上线节奏 | §10.7 |
| [06 记忆安全](06-security.md) | 数据即指令、信任分层、指令-数据隔离、注入检测、蜜罐 | §10.5 |
| [07 生产架构与 MCP 互操作](07-production-mcp.md) | 服务拆分、Build vs Buy、MCP 接口形态 | §5.1、§8 |

## 核心框架：记忆的原子操作

记忆系统可被诊断为「表示 × 操作」矩阵（arXiv:2505.00675 一类综述的框架），六个原子操作：

1. **巩固（Consolidation）**：短期 → 长期
2. **更新（Update）**：冲突解决、合并
3. **索引（Indexing）**：结构化 + 向量
4. **遗忘（Forgetting）**：衰减、淘汰
5. **检索（Retrieval）**：召回、重排
6. **压缩（Compression）**：摘要、蒸馏

ANDM 在六操作之外新增两个治理操作：**审核（Governance/quarantine）** 与 **版本绑定失效（commit-bound invalidation）**——这是相对所有参照系统的差异点。
