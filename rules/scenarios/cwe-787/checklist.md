<!-- 场景 checklist：注入 reviewer 的检测清单（MVP 设计 §2.4 三元组之一）
     本文件只含通用技术模式；团队私有口径请以 origin=team-asset 的场景目录承载 -->
# cwe-787 · out-of-bounds-write

写越界：向缓冲区写入超出其分配大小的数据（CWE-CWE-787）

## 检测信号
- memcpy/strcpy/sprintf/sprintf 族目标缓冲区大小与源长度未核对
- 数组索引来自外部输入或变量且无上界检查
- 指针算术可能越过分配边界（p + n 越过 p+cap）
- 循环边界 off-by-one（<= 配 < 混用）
- alloca/VLA 栈分配尺寸来自变量

## 安全模式（修复方向）
- 改用带目标大小的拷贝原语（memcpy_s/strlcpy/snprintf）
- 索引写入前显式断言 idx < size
- 优先 std::vector/std::string 等托管容器替代裸数组
- 对长度参与的大小计算做溢出检查

## 输出要求
- 仅报告与本场景检测信号相关的 finding；每条必须带 file:line 与成因一句话
- 无证据不报；置信度 <80 不报
