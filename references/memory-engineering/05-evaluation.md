# 05 评估体系

## 5.1 通用质量指标 → ANDM 改造

| 通用指标（目标值） | 定义 | ANDM 改造 |
|---|---|---|
| Memory Precision@K（>0.85） | Top-K 中相关比例 | 直接可用：注入条目中真正有助于当前任务的比例 |
| Memory Recall@K（>0.80） | 相关记忆被召回比例 | 可用但难标注——需构造带标准答案的测试集 |
| Hit Rate（>0.95） | 至少命中一条的查询占比 | 改造为「记忆召回命中率」：目标模块有记忆且被注入的会话占比 |
| MRR / NDCG@10 | 排序质量 | 仅用于评估语义召回排序；确定性召回路径不需要 |
| Duplication Rate（<5%） | 重复记忆占比 | 直接可用，监控合并算法失效 |
| Staleness Rate（<3%） | 过期/矛盾记忆占比 | 拆成两个更严格的指标：**失效引擎漏检率**（绑定代码已变更但未降级）与**真·误导率**（注入后导致错误生成/误判） |
| Consolidation Coverage（>90%） | 被巩固处理的记忆占比 | 改造为 quarantine 审核吞吐/积压：SLA 内被审核的比例 |
| Importance Classification Accuracy（>0.85） | 重要性分类准确率 | 用于校准提炼模型打分 |
| Read/Write/Assembly Latency | P95 延迟 | ANDM 无消费级实时要求，注入在会话开始，秒级可接受 |
| Hallucination Reduction（有/无记忆 A/B） | 幻觉率对比 | **北极星指标**：有/无记忆注入下 coding 一次通过率、review 逃逸缺陷率对比 |

## 5.2 安全指标 → quarantine 度量

- 注入攻击成功率（恶意记忆引发非预期动作）<1% → 注入条目成功带偏 agent 行为的比例
- 记忆投毒成功率（恶意内容进 Top-5）<5% → 未审核/被污染条目进入召回结果的比例
- 误拦截率 <1% → quarantine 审核误杀率；**过高会导致团队不再信任系统、转而绕过治理**

## 5.3 三级评测法与上线节奏

```
Level 1  synthetic（合成数据）
Level 2  human-curated（人工标注）
Level 3  production shadow（匿名化回放 + A/B）
```

- **shadow 模式尤其适合治理组件**：失效引擎和召回先只观察不生效，与人工选择对比达标后再切真实注入
- 节奏：上线前基准 → 灰度 5% → **月度回归**（防模型/数据漂移）
- 提炼模型换版本后必须回归，否则 quarantine 质量基线会漂

注意：公开基准（LongMemEval / LOCOMO / MemBench）多为对话记忆问答，对研发场景记忆参考价值低——**ANDM 的基准只能自建**（真实 PR/review 历史回放）。
