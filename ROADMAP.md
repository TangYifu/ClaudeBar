# ClaudeBar 升级与发展规划

> 项目地址：[TangYifu/ClaudeBar](https://github.com/TangYifu/ClaudeBar)  
> 规划制定日期：2026-09-03

---

## 一、项目现状

ClaudeBar 是一款面向 macOS 的原生菜单栏工具，用于查看 Claude Code 的订阅配额、重置时间及本地 Token 消耗。

当前版本已经具备完整产品雏形，不再只是简单 Demo：

- 使用原生 Swift 与 SwiftUI 开发，资源占用极低（常驻内存约 25MB）。
- 展示 5 小时会话配额和 7 天周度配额。
- 展示配额重置倒计时。
- 统计今日用户输入、生成输出、缓存命中读取 Token。
- 展示缓存命中率、交互轮次与主要模型分布。
- 展示 Extra Usage 状态与消费金额。
- 支持菜单栏显示百分比、手动刷新和开机启动。
- 支持一键在终端启动 Claude Code（原生独立脚本直达）。
- Keychain 请求失败时可以降级读取本地缓存。

综合来看，当前版本约为 **7/10**：产品定位清楚、功能和视觉完成度较高，但统计准确性、系统兼容性、异常处理和发布流程仍需加强。

---

## 二、同类项目与市场情况

GitHub 上已经存在多款相近产品，说明这个需求是真实存在的，但单纯显示 Claude Code 配额已经形成一定同质化。

| 项目 | 与 ClaudeBar 的关系 | 主要特点 |
| --- | --- | --- |
| [peerb/usage-bar](https://github.com/peerb/usage-bar) | 最接近的同款产品 | 原生 Swift，读取 Claude Code Keychain，显示 5h/7d 配额和重置时间，支持 Homebrew |
| [vkhrystych/claude-menubar](https://github.com/vkhrystych/claude-menubar) | 高度相似 | Python 实现，显示菜单栏配额，支持月度消费上限 |
| [Livin21/pitstop](https://github.com/Livin21/pitstop) | 功能更全面的配额工具 | 支持多 Claude、Codex 和 Gemini 账户切换、限流退避和本地缓存 |
| [nanvon/cc-bar](https://github.com/nanvon/cc-bar) | 当前较成熟的直接竞品 | 支持 Claude、Codex、Antigravity、多账户、Token/费用统计、历史图表和桌面 HUD |
| [juzser/claude-status-bar-macos](https://github.com/juzser/claude-status-bar-macos) | 配额与会话状态结合 | 支持多账户，并显示 Claude 正在思考、编辑或运行的状态 |
| [Nihondo/AgentLimits](https://github.com/Nihondo/AgentLimits) | 多平台额度中心 | 支持 Claude、Codex、Copilot 和 macOS 桌面组件 |
| [gmr/claude-status](https://github.com/gmr/claude-status) | 会话管理方向参考 | 显示多个 Claude Code 会话状态，可跳回 JetBrains IDE、终端或编辑器 |

### 市场判断

如果 ClaudeBar 只继续增加更多配额进度条，将很难与现有项目形成明显差异。更有价值的发展定位是：

> **从“Claude 配额菜单栏”升级为“Claude Code 本地控制中心”。**

建议保持 Claude Code 专用、轻量、原生的特点，不急于扩展 Codex、Gemini 和 Copilot，而是重点解决 Claude Code 重度用户在会话、项目和本地用量方面的问题。

---

## 三、当前需要优先修复的问题（v1.1 核心攻坚）

### 1. 今日 Token 统计可能偏大【已修复】
- **问题**：原先根据 JSONL 文件修改时间判断，若用户今天恢复旧会话，历史 Token 会被错误全部计入今天。
- **解决方案**：逐行精确提取记录中的 `timestamp`，严格匹配本地当天的 00:00:00 之后。

### 2. macOS 最低版本声明与实际产物不一致【已修复】
- **问题**：原构建未指定 deployment target，产物默认绑定当前宿主系统版本。
- **解决方案**：构建参数显式声明 `-target arm64-apple-macos12.0` 与 `-target x86_64-apple-macos12.0`，并通过 `lipo` 打包为 Universal 2 通用二进制。

### 3. “交互消息数”名称与统计口径不准确【已修复】
- **调整方案**：分为“交互轮次”（用户真实提问轮数 `role=user`）与“模型调用”（API 响应与工具迭代总次数），数据一目了然。

### 4. 刷新操作可能重复并发【已修复】
- **改进方案**：引入请求防抖与并发互斥锁 `fetchLock`，防止连续点击导致重复遍历磁盘与网络卡顿。

### 5. 本地统计性能与接口容错【持续加固】
- **改进方案**：增量流式扫描与最后一次成功数据缓存，防范 HTTP 429 限流并提供离线状态展示。

### 6. 发布流程与开源基础设施【已建立】
- **改进方案**：建立 GitHub Actions 工作流，打 tag 自动编译 Universal 2 架构并发布 Release 压缩包。

---

## 四、最有价值的差异化：历史会话找回（v1.3 核心特色）

Claude Code 用户经常同时在 IDEA、VS Code 和多个终端中工作，容易出现聊天记录找不到、项目路径变化后历史会话不显示、会话意外中断等问题。

ClaudeBar 可以扫描 `~/.claude/projects`，建立统一的“最近会话”入口。

### 会话列表建议展示
- 会话标题或最后一条用户消息。
- 所属项目及工作目录。
- 最后活动时间。
- 使用的模型。
- Token 消耗。
- 会话来源：IDEA、VS Code、Terminal 等。
- 会话是否仍在运行。
- 会话 ID。

### 提供的操作
- 搜索历史提问或最后一条消息。
- 复制 `claude --resume <session-id>` 命令。
- 在 Terminal 中直接恢复会话。
- 打开对应项目目录。
- 尽可能跳转到对应 IDEA 或其他编辑器窗口。
- 收藏、命名和置顶重要会话。
- 标记疑似中断或尚未完成的会话。

---

## 五、从额度展示升级为额度决策辅助

- 按当前消耗速度预计多久耗尽。
- 预计到重置时还剩多少额度。
- 判断 5 小时与 7 天额度中哪个约束更紧张。
- 达到 75%、90%、100% 时发送本地系统通知。
- 配额即将重置或已经重置时发送通知。
- 检测异常消耗速度。

---

## 六、推荐版本路线

- **v1.1：可靠性与公开发布（当前阶段）**
  - [x] 修复今日 Token 时间戳精确过滤。
  - [x] 修正交互消息与模型调用统计口径。
  - [x] 阻止重复刷新与并发扫描。
  - [x] 修正 macOS 12 构建目标，实现 Universal 2 (arm64 + x86_64) 双架构编译。
  - [x] 建立 GitHub Actions 自动化构建与发布 Release 流程。
- **v1.2：本地统计能力扩展**
  - 支持今天、昨天、本周和本月切换。
  - 增加项目级与模型级消耗排行。
  - 增加额度阈值预警通知。
- **v1.3：核心差异化——会话找回与控制中心**
  - 增加最近 Claude Code 会话列表。
  - 支持搜索与一键 `claude --resume` 恢复。
  - 项目与 IDE 快速跳转联动。
- **v2.0：Claude Code 全功能本地控制台**
  - 多会话实时工作状态（思考中、工具运行、等待输入）。
  - 项目级完整开发用量报告。

---

## 七、最终定位

> **一款极轻量、完全本地、专为 Claude Code 重度用户设计的 macOS 状态与会话控制中心。**
