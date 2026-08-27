---
name: cwe-190-integer-overflow
description: 整数溢出/回绕（CWE-CWE-190）。
cwe: 190
severity_default: important
origin: project-scenario
paths: ["**/*.{c,h}", "**/*.{cc,cpp,hpp}"]
---
# cwe-190 · integer-overflow

整数溢出/回绕（CWE-CWE-190）

## 检测信号
- 乘法求大小（n * size）未做溢出检查即用于分配
- 有符号整型溢出（UB）参与运算或比较
- 宽窄转换截断（size_t→int/int32）丢高位
- 无符号回绕值用于边界判断

## 安全模式（修复方向）
- __builtin_*_overflow / checked arithmetic 家族
- 大小计算先升宽类型、再校验合理上限
- 对外部来源数值先范围校验再参与运算

## 输出要求
- 仅报告与本场景检测信号相关的 finding；每条必须带 file:line 与成因一句话
- 无证据不报；置信度 <80 不报
