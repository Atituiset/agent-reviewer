<!-- 场景 checklist：注入 reviewer 的检测清单（MVP 设计 §2.4 三元组之一）
     本文件只含通用技术模式；团队私有口径请以 origin=team-asset 的场景目录承载 -->
# cwe-416 · use-after-free

释放后使用：访问已释放内存（CWE-CWE-416）

## 检测信号
- free/delete/realloc 之后同一指针仍被读写
- free 后的错误分支/early-return 路径仍引用该指针
- 双重 free 或重复 close
- 容器 erase/remove 后继续使用失效迭代器/引用
- 回调/异步任务捕获裸 this 或裸指针，对象生命周期更短

## 安全模式（修复方向）
- free 后立即置 NULL 并避免别名
- 所有权唯一化（unique_ptr/shared_ptr 明确、Rust/Arc）
- erase 使用返回的新迭代器
- 异步回调持有弱引用或在完成回调中校验存活

## 输出要求
- 仅报告与本场景检测信号相关的 finding；每条必须带 file:line 与成因一句话
- 无证据不报；置信度 <80 不报
