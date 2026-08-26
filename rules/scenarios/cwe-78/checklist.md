<!-- 场景 checklist：注入 reviewer 的检测清单（MVP 设计 §2.4 三元组之一）
     本文件只含通用技术模式；团队私有口径请以 origin=team-asset 的场景目录承载 -->
# cwe-78 · os-command-injection

OS 命令注入：外部输入进入 shell 执行（CWE-CWE-78）

## 检测信号
- system/popen/exec*('sh','-c',…) 拼接了用户输入或外部字符串
- 反引号/$() 内插入外部变量
- 文件名、URL 参数等间接外部串直接拼进命令行
- 拼接前仅做了引号包裹（可被内嵌引号逃逸）

## 安全模式（修复方向）
- 参数数组式 exec（execve/subprocess 列表参数）绕开 shell
- 确需 shell 时对外部串做严格白名单字符校验
- 能库调用不落命令（如用 tar 库而非 tar 命令）

## 输出要求
- 仅报告与本场景检测信号相关的 finding；每条必须带 file:line 与成因一句话
- 无证据不报；置信度 <80 不报
