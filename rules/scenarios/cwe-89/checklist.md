<!-- 场景 checklist：注入 reviewer 的检测清单（MVP 设计 §2.4 三元组之一）
     本文件只含通用技术模式；团队私有口径请以 origin=team-asset 的场景目录承载 -->
# cwe-89 · sql-injection

SQL 注入：外部输入拼进 SQL 文本（CWE-CWE-89）

## 检测信号
- 字符串拼接/f-string/format/% 组装 SQL
- ORM raw/query 接口携带未绑定的用户参数
- 表名/列名/排序方向等标识符动态拼接
- LIKE 条件通配符未转义（%/_）

## 安全模式（修复方向）
- 参数化查询/prepared statement 是唯一 SQL 通道
- 标识符用代码内白名单映射，禁止外部串直拼
- 排序方向等枚举值先映射再入库

## 输出要求
- 仅报告与本场景检测信号相关的 finding；每条必须带 file:line 与成因一句话
- 无证据不报；置信度 <80 不报
