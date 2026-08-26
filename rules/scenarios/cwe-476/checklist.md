<!-- 场景 checklist：注入 reviewer 的检测清单（MVP 设计 §2.4 三元组之一）
     本文件只含通用技术模式；团队私有口径请以 origin=team-asset 的场景目录承载 -->
# cwe-476 · null-pointer-dereference

空指针解引用（CWE-CWE-476）

## 检测信号
- malloc/calloc/new 及各类 find/get/lookup 返回值未判空即解引用
- 错误路径约定返回 NULL 但部分调用方不检查
- map/dict 取值后直接 -> 或 .method()
- 把可能为空的指针传入内部约定非空的函数

## 安全模式（修复方向）
- 分配/查找结果立即判空并走错误处理
- 语言层用 Optional/可抛异常的访问器替代裸返回
- 构造即完整初始化（RAII），不留半成品对象

## 输出要求
- 仅报告与本场景检测信号相关的 finding；每条必须带 file:line 与成因一句话
- 无证据不报；置信度 <80 不报
