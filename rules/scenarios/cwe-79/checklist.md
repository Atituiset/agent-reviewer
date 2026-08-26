<!-- 场景 checklist：注入 reviewer 的检测清单（MVP 设计 §2.4 三元组之一）
     本文件只含通用技术模式；团队私有口径请以 origin=team-asset 的场景目录承载 -->
# cwe-79 · xss

跨站脚本：不可信数据进入 HTML 上下文（CWE-CWE-79）

## 检测信号
- 用户输入写入 innerHTML/outerHTML/dangerouslySetInnerHTML/document.write/v-html
- 模板关闭自动转义（{{{ }}}、|safe、|raw）承载动态数据
- 动态 URL 进入 href/src 且允许 javascript:/data: 协议
- 服务端渲染拼接 HTML 片段未编码

## 安全模式（修复方向）
- 默认文本通道渲染（textContent/自动转义模板）
- 富文本走白名单净化器（DOMPurify 等）
- URL 白名单协议校验；CSP 作为纵深防御

## 输出要求
- 仅报告与本场景检测信号相关的 finding；每条必须带 file:line 与成因一句话
- 无证据不报；置信度 <80 不报
