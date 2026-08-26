<!-- 场景 checklist：注入 reviewer 的检测清单（MVP 设计 §2.4 三元组之一）
     本文件只含通用技术模式；团队私有口径请以 origin=team-asset 的场景目录承载 -->
# cwe-798 · hardcoded-credentials

硬编码凭据（CWE-CWE-798）

## 检测信号
- 源码/配置中的字面量 password/api_key/token/secret
- PEM 私钥块出现在仓内任何文件
- 数据库/服务连接串内嵌凭据
- 注释或测试中遗留真实账号

## 安全模式（修复方向）
- 环境变量或密管系统（Vault/KMS/Secret Manager）注入
- .env 加入 .gitignore 并提供 .example 模板
- 已泄漏的密钥视为失陷：轮换而非删除了事

## 输出要求
- 仅报告与本场景检测信号相关的 finding；每条必须带 file:line 与成因一句话
- 无证据不报；置信度 <80 不报
