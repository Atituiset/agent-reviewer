---
name: cwe-22-path-traversal
description: 路径穿越：外部输入逃出基目录（CWE-CWE-22）。
cwe: 22
severity_default: high
origin: mitre-top25
paths: ["**/*.java", "**/*.py", "**/*.{js,jsx,mjs,cjs}", "**/*.{ts,tsx}", "**/*.go", "**/*.php", "**/*.rs", "**/*.{cc,cpp,hpp}"]
---
# cwe-22 · path-traversal

路径穿越：外部输入逃出基目录（CWE-CWE-22）

## 检测信号
- 路径拼接用户输入后 open/read/write/unlink 未归一化校验
- 未拒绝 '..' 段与绝对路径覆盖
- 压缩包解压 entry name 未校验（Zip Slip）
- resolve/realpath 后未验证仍在基目录内

## 安全模式（修复方向）
- normalize/resolve 后强制 startsWith(基目录)
- 拒绝绝对路径与 .. 段；文件名取 basename
- 解压逐项校验目标路径

## 输出要求
- 仅报告与本场景检测信号相关的 finding；每条必须带 file:line 与成因一句话
- 无证据不报；置信度 <80 不报
