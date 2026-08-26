<!-- 场景 checklist：注入 reviewer 的检测清单（MVP 设计 §2.4 三元组之一）
     本文件只含通用技术模式；团队私有口径请以 origin=team-asset 的场景目录承载 -->
# cwe-401 · memory-leak

内存泄漏：分配后所有路径均未释放（CWE-CWE-401）

## 检测信号
- 逐个 alloc 对照：每条 early-return/throw 路径是否都释放
- realloc 失败时原块指针被覆盖导致丢失
- fd/socket/handle 打开后的失败路径未关闭
- 缓存/registry 只增不减无淘汰

## 安全模式（修复方向）
- 统一清理出口（goto cleanup / defer / RAII 析构）
- realloc 结果先接临时变量
- 缓存加容量上限与淘汰策略

## 输出要求
- 仅报告与本场景检测信号相关的 finding；每条必须带 file:line 与成因一句话
- 无证据不报；置信度 <80 不报
