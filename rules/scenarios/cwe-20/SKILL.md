---
name: cwe-20-input-validation
description: 输入校验缺失：外部输入未经约束即使用（CWE-CWE-20）。
cwe: 20
severity_default: medium
origin: mitre-top25
paths: ["**/*"]
---
# cwe-20 · input-validation

输入校验缺失：外部输入未经约束即使用（CWE-CWE-20）

## 检测信号
- 外部输入直接作为数值/枚举/路径/正则使用
- 反序列化不可信数据无 schema/类型校验
- limit/offset/count 类参数无上界
- bool/enum 语义字段接受任意串

## 安全模式（修复方向）
- 入口处集中校验（类型、范围、白名单）
- 结构化输入过 schema 验证层再进业务
- 资源类参数一律带上界

## 输出要求
- 仅报告与本场景检测信号相关的 finding；每条必须带 file:line 与成因一句话
- 无证据不报；置信度 <80 不报
