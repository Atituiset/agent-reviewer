<!-- 场景 checklist：注入 reviewer 的检测清单（MVP 设计 §2.4 三元组之一）
     本文件只含通用技术模式；团队私有口径请以 origin=team-asset 的场景目录承载 -->
# cwe-362 · race-condition

竞态条件：共享状态访问缺乏同步（CWE-CWE-362）

## 检测信号
- 多线程共享可变状态且全路径无锁保护
- check-then-act 序列（exists→open、get→set、if(!flag) flag=true）
- 锁保护范围漏掉某一条写路径
- signal handler / 中断上下文执行非 async-safe 操作
- 惰性初始化无双检正确性保障

## 安全模式（修复方向）
- 共享状态全部路径持同一把锁或用原子类型
- check 与 act 合并为单步原子操作
- handler 只做置标志类 async-safe 动作
- 并发改动跑 TSan/RaceDetector 回归

## 输出要求
- 仅报告与本场景检测信号相关的 finding；每条必须带 file:line 与成因一句话
- 无证据不报；置信度 <80 不报
