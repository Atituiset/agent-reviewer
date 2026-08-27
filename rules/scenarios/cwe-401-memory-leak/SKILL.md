---
name: cwe-401-memory-leak
description: 内存泄露检测。评审 C/C++ 动态内存/资源申请与释放路径时调用，关注所有退出路径（含异常、错误分支）上的配对释放。
cwe: 401
severity_default: high
paths: ["**/*.{c,cc,cpp,h,hpp}"]
---

# CWE-401 内存泄露 评审清单

对 diff 中每个资源申请点（`malloc/calloc/new/new[]/strdup/ fopen/socket/句柄类 API`），追踪其所有权的完整生命周期：

## 1. 每条退出路径都释放了吗

- 正常路径、错误分支、`goto` 链、提前 `return`、异常抛出路径——逐条走查，遗漏任何一条即泄露
- 新增的错误处理分支是否只释放了部分已申请资源？（多资源申请的部分释放是最常见模式）
- 循环内申请：某次迭代失败 break/return 时，本次及历次迭代申请的资源是否释放？

## 2. 所有权转移清晰吗

- 指针交给容器/回调/另一个线程后，释放责任归谁？转移后原位置是否还二次释放（double free，联动 cwe-415）？
- 函数返回堆对象：调用方契约是否明确负责释放？本 diff 是否改变了该契约？
- `realloc` 模式：是否先存临时变量，避免失败时原块泄露？

## 3. 惯用法

- C++ 是否可用 RAII（`std::unique_ptr`/`std::vector`/lock_guard）替代手工 new/delete？diff 中绕过 RAII 的手工管理需重点说明理由
- 析构函数、拷贝/移动语义三者（Rule of Three/Five）是否成套？diff 只改了其中之一是高危信号

## 输出要求

仅报告**存在具体未释放路径**的 finding：给出 `file:line`、申请点、未覆盖的退出路径。风格性建议（"建议改用智能指针"但无实际泄露路径）降级为 minor。
