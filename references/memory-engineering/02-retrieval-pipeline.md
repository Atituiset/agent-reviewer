# 02 检索 Pipeline

## 2.1 读写双管线分离

- **Write**：`PREPROCESS → IMPORTANCE → DEDUP → STORE` + 异步 consolidation queue
- **Read**：`QUERY EXPANSION → HYBRID SEARCH → RANKING → CONTEXT ASSEMBLY`

两条管线完全解耦。ANDM 的 quarantine 插在写管线的 STORE 之前（§10.1）。

## 2.2 写入时重要性评分

通用公式（消费级场景）：

```
Importance = w1×UserExplicitMention + w2×EmotionalIntensity + w3×TopicNovelty
           + w4×InformationDensity + w5×FutureReferenceLikelihood + w6×InteractionDepth
```

ANDM 改造为研发信号（§10.3）：

```
Importance = w1×ReviewSeverity + w2×DecisionFinality + w3×ModuleCriticality
           + w4×InfoDensity + w5×FutureReferenceLikelihood
```

重要性分的用途：决定 quarantine 审核优先级 + 入库后的初始权重。

## 2.3 混合检索与排序

**三维评分（Generative Agents）+ 生产化多信号融合**：

```
recency(m) = exp(-λ × Δt)    # Δt = 距上次被访问的时间，检索命中即重置（复述效应）
```

要点：**时效衰减锚定 last_accessed，不是 created_at**——被反复召回的条目保鲜。

各检索路径的适用边界：

| 路径 | 擅长 | ANDM 用途 |
|---|---|---|
| 向量 | 语义泛化 | 跨模块的泛化经验 |
| BM25/关键词 | 精确术语、名称、日期 | **代码标识符、错误码、配置键**（向量检索不理解精确关键词） |
| 结构化过滤 | 确定性归属 | **模块路径匹配**（ANDM 主路径，权重最高；通用系统通常没有这条） |

ANDM 排序信号新增两项：`ModulePathMatch`（主信号）与 `BindingValidity`（绑定代码版本仍有效？失效条目**直接过滤**而非降权——见 05 的误导率指标）。

## 2.4 Context Assembly 三策略

1. **Top-K + 主题多样性**：避免注入内容集中于单一主题
2. **层级注入**：最重要的全文放前面，次要的折叠为一行摘要——ANDM 映射：高信任条目全文注入，低信任/旧条目只注入摘要
3. **引用格式**：`[Memory #123] 2026-07-15: ...`——条目带 ID + 来源引用注入，便于 agent 在输出中引用，也便于事后度量「哪条记忆影响了这次生成」（命中率度量的埋点基础，§10.2）

## 2.5 写入前去重

LSH 快速近似 + cosine > 0.95 合并 + 时间窗口合并。

ANDM 对应：去重应在**进 quarantine 之前**完成，避免审核人重复审近似条目（§10.3）。
