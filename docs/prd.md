# ulooi PRD（产品需求文档）

**日期：** 2026-05-17
**版本：** v0.1 — 初版，对应 M0 umbrella spec
**关联文档：**
- [M0 umbrella spec](https://github.com/novolei/uclaw-new/blob/main/docs/superpowers/specs/2026-05-17-ulooi-design.md)（跨项目程序设计，住在 uclaw repo）
- [总体框架设计 `architecture.md`](./architecture.md)（技术实现层面）

---

## 1. 产品愿景

**ulooi 让 UCLAW Agent 拥有真正的实体身体。**

用户家里的 Looi 玩具机器人 + 一台 iPhone（旁置或 docked）+ macOS/Windows 上的 UCLAW，构成一个"同一个 Agent 在三处同时在场"的实体化 AI 助手。机器人会转头、亮灯、被摸时反应；iPhone 是它的"嘴"和"眼"；UCLAW 桌面端是它的"大脑"。三端实时联动，UCLAW 关机时仍能基本对话。

**一句话定位：** UCLAW Agent 的实体化前端，让"我的 AI 助手"从屏幕里走到客厅里。

---

## 2. 目标用户

### Persona 1 — Ryan（"我自己"型，v1 唯一明确画像）

- 已经在用 UCLAW 桌面端做日常工作（开发、记事、对话）
- 拥有/愿意购买一台 Looi 机器人作为"实体化"实验
- 技术背景：会装 Tailscale、能扫 QR 码配对
- 想要的：把已经熟悉的 UCLAW Agent 从"打开 app 才有"变成"客厅里一直在"
- 不想要的：再注册一个云账号、再多一个 AI 助手品牌

### Persona 2 — Ryan 家人（被动用户，v1 关注但不优化）

- 不懂技术，但客厅里有这个机器人就会跟它说话
- 关心：能不能听懂中文、有没有奇怪的隐私监听、会不会突然吓人
- 不关心：Agent 用的什么模型、UCLAW 是什么

### v1 不优化的 Persona（明确推后）

- 完全没用过 UCLAW 桌面端的"独立 ulooi 用户" —— v1 强依赖 UCLAW，不是 standalone 产品
- 商业用户 / 企业 —— 不在视野
- iPad-only 用户 —— iPad 适配在 M1 spec 决定，v1 主要为 iPhone 设计

---

## 3. 用户场景（Stories）

### Golden Path（每个里程碑兑现一段）

**S0 — 第一次拆箱（M0.5 + M1）**

> Ryan 拆开 Looi 包装，下载 ulooi，扫机器人底部 QR 码完成 BLE 配对。点 "挥手" 按钮，机器人挥手了。点 "灯光红色"，机器人变红。

DoD：30 秒内完成首次配对；点按钮到机器人响应延迟 < 200ms。

**S1 — 连上 UCLAW（M2）**

> Ryan 打开 macOS 上的 UCLAW，看到右上角弹通知"ulooi 想配对"。点接受，扫 UCLAW 显示的 QR。回到 iPhone，看到 ulooi 显示 "Connected to Ryan's Mac"。

DoD：配对总耗时 < 60s；配对状态持久化；下次启动自动重连。

**S2 — 第一次对话（M3）**

> Ryan 把 iPhone 立在 Looi 旁边。说："Hey Looi, what's on my calendar today?"
> Looi 灯光蓝色闪烁（思考中）→ 1.5s 内 iPhone 出声 "You have a meeting at 3pm..."，同时 Looi 灯光按说话节奏脉动 + 小幅头部摆动。
> 打开 macOS UCLAW，"Looi 客厅" space 里的 ambient session 已经显示这段对话。

DoD：唤醒词识别准确率 > 95%；用户停说话到首字延迟 < 1.5s；UCLAW 端实时同步。

**S3 — 三端同在（M4）**

> Ryan 在 macOS UCLAW 里开始打字 "帮我查……"
> 客厅里 Looi 头部轻微转向 Ryan，灯光呈现"注意倾听"色。
> Ryan 走过去摸 Looi 头顶。
> macOS UCLAW 右下角弹 toast "Looi felt a touch"。

DoD：状态同步延迟 < 300ms；触摸事件可靠送达。

**S4 — UCLAW 关机时仍能对话（M5）**

> Ryan 出门前关了 macOS。回家后 Looi 还亮着待命灯。
> 说 "Hey Looi, 我回来了"，机器人回应 "欢迎回家"（用 Apple Foundation Model，本地推理）。
> Ryan 问 "我的日历呢？"，机器人诚实回答 "等 UCLAW 上线我才能查，我先记下你问过"。
> 打开 macOS，UCLAW 启动后 5s 内 Looi 主动开口："你刚才问的日历是这样的……"

DoD：黄段降级状态切换 < 5s；离线事件零丢失；恢复后摘要回放。

**S5 — 它"看到"东西（M6）**

> Ryan 拿一个新买的水果给 Looi 看："Looi 看这是什么？"
> Looi 灯光从红过渡到绿（提示摄像头激活），iPhone 屏幕显示"Looi is looking"。
> 1-2s 后回答："那看起来像火龙果，外面粉红色、绿色苞片。"

DoD：摄像头激活前必须显式提示（灯+UI 双提示）；识别准确率 > 80%。

**S6 — 它认得家人（M7 + M8）**

> Ryan 老婆走进客厅说："Looi 帮我提醒晚上 8 点煮饭。"
> Looi 把这个提醒挂在 "Lisa" 名下而不是 "Ryan" 名下。
> 一周后 Ryan 问 UCLAW："Lisa 最近都让你做了什么？"
> UCLAW 回答时引用了那条提醒。

DoD：说话人识别准确率 > 90%（家庭 ≤ 4 人）；memory_graph 写入 source='ulooi' 标记齐全。

### Edge / Negative Cases（v1 要处理的"不完美时刻"）

- **机器人没电了** → Looi 灯光闪烁红色 3 次后熄灭；iPhone UI 出现 "Looi is sleeping" 占位；Agent 仍可以从 iPhone 对话
- **iPhone 锁屏太久 BLE 后台被回收** → 用户解锁 iPhone 时自动重连 + 提示 "I lost touch with Looi for a moment"
- **配对 token 过期（90 天）** → 重连失败时自动触发滚动续期；只在续期也失败时要求 QR 重扫
- **小孩拼命摇晃 Looi** → motion 事件阈值超阈触发 "保护模式"（拒绝执行动作命令 30s）
- **Wi-Fi 不可达 UCLAW 但 BLE 正常** → 切黄段；UI 显式 badge
- **同时两个 iPhone 都想连同一台 Looi** → BLE 排他性，后连者被拒 + 提示用户

---

## 4. 功能需求

完整列表见 [M0 spec §3-§4](https://github.com/novolei/uclaw-new/blob/main/docs/superpowers/specs/2026-05-17-ulooi-design.md)。这里只列 PRD 视角的 P0 取舍：

### P0（v1 必有）

| 功能 | 用户能做什么 | 兑现里程碑 |
|---|---|---|
| 设备配对 | 扫 QR 码连 Looi 和 UCLAW | M1 + M2 |
| 语音对话 | 唤醒词触发，自然语言双向 | M3 |
| 三端 presence | 任一端动作另两端可感知 | M4 |
| 离线降级 | UCLAW 关机仍能对话 | M5 |
| 隐私指示 | 摄像头/麦克风激活时硬件级提示 | M3 + M6 |
| 设置面板 | 看连接状态、暂停麦克风、解除配对 | M1 + M2 |

### P1（v1 后续滚动）

| 功能 | 兑现里程碑 |
|---|---|
| 摄像头视觉 | M6 |
| 说话人识别 | M7 |
| 长期记忆写入 | M8 |

### 非目标（v1 明确不做）

- 没装 UCLAW 桌面端也能独立用
- 多 Looi 设备拓扑（一个 iPhone 配 N 台 Looi）
- 云端账号 / 跨账号分享
- Apple Watch / 其它平台
- 内购 / 订阅 / 广告

---

## 5. 非功能需求

### 性能

| 指标 | 目标 | 兜底 |
|---|---|---|
| 语音对话端到端延迟（用户停说话 → iPhone 出声） | < 1.5s | < 2.5s |
| BLE 命令往返 | < 100ms | < 300ms |
| 配对总耗时 | < 60s | < 120s |
| 启动到可用 | < 3s 冷启 | < 8s |
| 黄段降级切换 | < 5s | < 15s |

### 隐私

- 麦克风/摄像头激活时 Looi 灯光 + iPhone UI **双重显式提示**
- 所有音频/视觉数据走 iPhone 本地处理；只有"提取出的文本/事件"经加密通道送到 UCLAW
- 配对 token 存 iOS Keychain；BLE 通信无敏感数据（只 motion/light 命令 + 传感读数）
- 不走任何云中继（v1 全 P2P）
- 暂停麦克风开关在主屏一级位置，不藏在子菜单

### 可靠性

- 离线事件队列零丢失：iOS 本地 SQLite WAL；UCLAW 恢复后批量回放
- 协议 envelope 强幂等：所有事件带 ULID，UCLAW dedup
- 配对 token 90 天到期，到期前 7 天滚动续期，用户无感

### 无障碍

- VoiceOver 全覆盖
- 唤醒词识别支持中文 + 英文（其它语言推后）
- 所有视觉提示（机器人灯光状态）有对应的 iPhone UI 描述

### 兼容性

- iOS 18.2+（Apple Foundation Model 要求；M5 兑现前 18.0 + 也能用，只是黄段降级体验差）
- iPhone 12 及以上（CoreBluetooth 5.0 + 神经引擎性能）
- iPad 适配 M1 决定

---

## 6. 成功指标

### 北极星指标（v1 评估）

> **每日活跃对话次数 / iPhone 主动唤醒次数 ≥ 5**（持续使用一周后）

低于这个值说明体验没让用户养成习惯，本质上是"再做一次"的成本太高。

### 支持指标

| 指标 | 目标 | 测量方式 |
|---|---|---|
| 首次配对成功率 | > 90% | UCLAW 端 pairing 日志 |
| 黄段降级触发率 | < 5% / 日 | iOS 端状态机日志（匿名上报，opt-in） |
| 平均对话轮次 | > 3 | UCLAW agent_messages 计数 |
| memory_graph 增量（M8 后） | > 20 条 / 周 | UCLAW 端统计 |
| 用户主动开口频次（vs 用户在桌面端打字频次） | > 30% | UCLAW 端 source 统计 |

---

## 7. 关键 UX 流程

详细 wireframe 在 M1 spec；这里描述每个关键流程的核心步骤和决策点。

### 流程 A — 首次配对

1. App 启动 → 检测无配对 → 引导页 "找一台 Looi"
2. iPhone 蓝牙权限请求 → 扫描可见 Looi
3. 用户点列表中的 Looi 设备 → 扫机器人底部 QR（含 device-specific pairing salt）
4. BLE 连接 + 握手成功 → "找一台 UCLAW"
5. mDNS / Tailscale 扫描 UCLAW → 列表选 → 在 macOS UCLAW 上点确认 + 扫 QR
6. 完成 → 跳主屏

**关键 UX 决策（M1 spec）：** 这是单引导式还是用户可跳过中间步骤？建议单引导（首次配对是仪式感）。

### 流程 B — 主屏

主屏始终显示：
- Looi 当前状态（灯光 + 电量 + RSSI）
- UCLAW 连接状态（绿/黄/红 badge）
- 最近一次对话摘要
- 大按钮："暂停麦克风" + "解除配对" + "设置"

**关键 UX 决策（M1 spec）：** 是 iPhone 屏幕一直亮（docked 模式）还是只在交互时亮？建议提供模式开关。

### 流程 C — 对话进行中

- iPhone 屏幕全屏 ASR 实时转写气泡（用户语音）+ TTS 回答气泡（Agent 输出）
- Looi 灯光节奏 + 头动跟随
- 用户可随时点 "中断" 按钮停止 Agent

**关键 UX 决策（M3 spec）：** 转写气泡是逐字流式渲染还是分句渲染？建议逐字（体感更"它在听"）。

### 流程 D — 离线降级（黄段）

- 顶部状态条变黄："UCLAW offline — limited mode"
- 主屏出现一行小字 "I'll remember what you ask"
- 用户问到需要 UCLAW 的问题时，Agent 诚实说 "I'll need my main brain for that — I've noted it"
- 恢复时顶部条变绿 + Agent 主动一句话回顾

### 流程 E — 隐私事件

任何时候摄像头被激活：
- Looi 灯光从当前色平滑过渡到**绿色**（约定信号）
- iPhone 屏幕顶部红色 badge "Camera on"
- 用户可随时点 badge 立刻关摄像头

---

## 8. 风险 & 开放问题（PRD 视角）

技术风险在 [M0 spec §7](https://github.com/novolei/uclaw-new/blob/main/docs/superpowers/specs/2026-05-17-ulooi-design.md)；这里是产品视角的风险：

1. **iPhone 物理摆放方案** —— docked / 旁置 / 手持三种体感差很多。M1 spec 必须先做 UX prototype 决定推荐场景。
2. **声音定位错位感** —— TTS 从 iPhone 喇叭出而非 Looi 喇叭出，用户可能觉得"机器人不是在自己说话"。Lipsync coordinator 节拍同步是 mitigations，但需要 M3 实测体感。
3. **家人接受度** —— Persona 2（家人）首次见到客厅里有个会说话的机器人是否会反感？M3 后做家庭测试。
4. **隐私担忧的可见性** —— 即使我们做了双重提示，"有摄像头一直对着客厅"的事实可能让访客不舒服。是否需要"访客模式"（一键关闭所有感知）？M4 决定。
5. **唤醒词冲突** —— "Hey Looi" 是否会跟 Hey Siri 互相误触发？M3 实测。

---

## 9. 时间线

详见 [M0 spec §4](https://github.com/novolei/uclaw-new/blob/main/docs/superpowers/specs/2026-05-17-ulooi-design.md)。摘要：

- **M0.5 - M1**（≈ 2 周）：硬件可控 + iOS shell + 配对体验
- **M2 - M3**（≈ 4 周）：UCLAW 接入 + 语音对话
- **M4 - M5**（≈ 4 周）：三端同在 + 离线降级
- **M6 - M8**（v1 后滚动）：vision + speaker id + memory writeback

v1 (P0) 落地目标：**8 周内可日常使用，2026 年内迭代完成 P1**。

---

## 10. 决议日志

| 日期 | 决定 | 决议者 |
|---|---|---|
| 2026-05-17 | 架构选 reflex/cortex 分离（B） | 用户 + brainstorm |
| 2026-05-17 | v1 范围选 S3（full embodied） | 用户 + brainstorm |
| 2026-05-17 | 网络选 LAN + Tailscale | 用户 + brainstorm |
| 2026-05-17 | 会话模型选 embodied space + ambient | 用户 + brainstorm |
| 2026-05-17 | 音频/视频用 iPhone，Looi 不做音视频管道 | 用户明确纠正 |
| 2026-05-17 | iOS 技术栈选 Pure SwiftUI/Swift | 用户 + brainstorm |
| 2026-05-17 | ulooi 独立成 public repo | 用户 |
