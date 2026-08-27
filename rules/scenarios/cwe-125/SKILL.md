---
name: cwe-125-out-of-bounds-read
description: 读越界：读取超出缓冲区边界的数据（CWE-CWE-125）。
cwe: 125
severity_default: high
origin: mitre-top25
paths: ["**/*.{c,h}", "**/*.{cc,cpp,hpp}"]
---
# cwe-125 · out-of-bounds-read

读越界：读取超出缓冲区边界的数据（CWE-CWE-125）

## 检测信号
- 循环上界用了错误的长度变量（容量 vs 实际长度）
- memcmp/memcpy 的 len 参数大于任一侧缓冲区实际大小
- 解析定长头/结构体时未校验剩余报文长度
- 字符串处理后按旧长度继续读取

## 安全模式（修复方向）
- 读取前校验 offset + need <= remaining
- 长度变量单一来源化，避免容量/长度混用
- 边界解析用带限读取 helper

## 输出要求
- 仅报告与本场景检测信号相关的 finding；每条必须带 file:line 与成因一句话
- 无证据不报；置信度 <80 不报
