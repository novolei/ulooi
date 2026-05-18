# M0.5 Prototype Findings

**起：** 2026-05-17
**止：** 2026-05-17（单日完成）
**硬件：** LOOI Robot（轮子底座型，黄色 ABS 外壳，serial = `16A39MKFL7BH`）
**固件版本：** 未直接读到 firmware revision；通过 GATT 4 service + 14 main chars 推断为标准 Looi base firmware
**iOS 测试设备：** iPhone 真机（iOS 26.5 deployment target，build 系列 38519fe → 21e85c1）

> Probe v2 + 多次 push iteration 后达成所有核心目标。文档反映**已验证状态**，未验证项标注 `❓` 留给 M1 / 后续。

---

## 0. 操作流程（最终验证）

App 启动 → BLE state → poweredOn → **auto-reconnect 自动触发**（基于上次保存的 paired peripheral UUID）→ 走 connectAndAutoInitLooi：

1. `connect(savedID)` (5s 超时则走 scan-fallback 15s)
2. `auto-discoverServices` → 4 services + 28 chars 全部枚举（< 1s）
3. **Step 0/4**: read 2A29 (Manufacturer Name) — 仿 andrey-tut macOS cache wake-up
4. **Step 1/4 (INIT 1/3)**: write `0x01` → FEDA, sleep 100ms
5. **Step 2/4 (INIT 2/3)**: subscribe FED5 + FED9, sleep 300ms
6. **Step 3/4 (INIT 3/3)**: write `0x03` → FEDA
7. **Keep-alive 并行启动**：motor heartbeat (FED0, 30ms, `.withoutResponse`) + battery poll (FED8, 4s)
8. Looi 进入完全 ready 状态，会持续保持连接，并通过 FED9 notify 推送传感器数据

**手动配对路径（首次或 reset 后）：**Scan tab → Start Scan → 找到 `LOOI Robot` → 点 **`⚡ Connect + Init Looi`**（不是普通 `Connect`，那个会被 Looi 立刻 drop）。成功握手后自动保存 UUID 到 UserDefaults，下次 app 启动自动复连。

---

## 1. GATT 拓扑（实测，verified）

| 服务 UUID | Chars 数 | 用途 |
|---|---|---|
| `8018-...` | 4 | ❓ 未知（chars `8020/8021/8022/8023`，全 `write\|indicate`；推测固件升级或鉴权，M0.5 未触碰）|
| `180A-...` | 8 | 标准 GATT Device Information Service。读 `2A29` = manufacturer = `"16A39MKFL7BH"` 序列号 |
| `6E40-...-FF00` | 2 | Nordic UART 风格（`FF01` notify + `FF02` write）。`FF02` 写 `7F 00` ❌ 无响应（不是替代 motor 通道） |
| `00FF` | 14 | **主 Looi 服务** — 全部 motor / sensor / light / handshake chars 都在这里 |

### `00FF` service 内 14 个 chars 完整功能映射

| Char | Properties | 实测用途 | 状态 |
|---|---|---|---|
| `FED0` | r/w/wnr/notify | **Movement** — 2-byte signed Int8 `[speed, turn]` | ✅ verified |
| `FED1` | r/w/wnr/notify | **Head** — 1-byte angle 0x00..0xFF, center=0x5A | ✅ verified |
| `FED2` | r/w | **Light** — 1-byte intensity，`0x00`=off，其它=亮度梯度 | ✅ verified |
| `FED3` | w-only | ❓ 未知 | ⚠️ 未测 |
| `FE00` | r/w/notify | **Rich command** — 17-byte coordinated animation packet | ⚠️ M3 lipsync 时再探 |
| `FED5` | r/w/notify | **Sensors stream**（subscribed in INIT，但本次未观察到 packets，推测需特定 actuator 交互触发）| ✅ subscribed |
| `FED6` | r/notify | ❓ 未知 notify channel | ⚠️ 未测 |
| `FED7` | r/w | ❓ 未知 | ⚠️ 未测 |
| `FED8` | r/notify | **Battery** — 2-byte `[percent, status]`，本次实测 `35 00` = 53% | ✅ verified |
| `FED9` | r/notify | **Telemetry multi-packet stream**（详见 §3） | ✅ verified + decoded |
| `FEDA` | r/w/notify | **Handshake** — write `0x01` → wait → write `0x03` | ✅ verified |
| `FEDF` | w-only | ❓ 未知 | ⚠️ 未测 |
| `FED4` | r/wnr | ❓ 未知 | ⚠️ 未测 |
| `FEF0` | r/w/notify | ❓ 未知 | ⚠️ 未测 |

---

## 2. 命令验证（实测）

### 2a. Handshake（必须完成否则 Looi 在 2s 内断开）

| 步骤 | UUID | bytes | 状态 |
|---|---|---|---|
| read | 2A29 | — | ✅（拿到序列号 ASCII `16A39MKFL7BH`）|
| write | FEDA | `01` | ✅ |
| notify subscribe | FED5 | — | ✅ |
| notify subscribe | FED9 | — | ✅（subscribe 后**立刻**收到 `notify←FED9: 11 01 00` 作为 boot status 确认）|
| write | FEDA | `03` | ✅ |

**关键时序：** write `0x01` → write `0x03` 之间必须 subscribe FED5/FED9 才能保持连接。andrey-tut Python 用 `asyncio.sleep(0.1)` 在 write 1 后等 100ms；我们 iOS 端 subscribe 后等 300ms 给 iOS CB descriptor write 完成时间。

### 2b. Movement (FED0)

| 命令 | bytes | 实测 | 备注 |
|---|---|---|---|
| stop | `00 00` | ✅ heartbeat 默认值 | |
| forward (max) | `7F 00` | ✅ 推得动 | 必须 `.withoutResponse` |
| backward (max) | `81 00` | ✅ 推得动 | -127 in signed Int8 |
| spin left (max) | `00 7F` | ✅ 原地左转 | |
| spin right (max) | `00 81` | ✅ 原地右转 | |
| 混合 | `46 46` 等 (speed + turn) | ✅ 同时前进+转向 | |

**🛑 关键安全机制 — Cliff Sensor Lockout：** 当 Looi 检测到**前端 cliff（轮子悬空）**时，会**主动忽略 motor 命令**直到检测到地面。`heartbeat` 仍在发送，FED9 telemetry 仍在 stream，但 motor 不会响应。这一度让我们以为 BLE/协议有问题（写了 1000+ heartbeat ticks 没反应）。**真正原因：Looi 被抬在桌上做测试**。放回地面后 Forward 立即工作。

**Heartbeat 必要性：** Looi 期望 movement 命令每 ~30ms 一次（即使 STOP），不然在 ~2s 内主动 drop 连接。
**Write mode：** 必须 `.withoutResponse`（match andrey-tut Python）；`.withResponse` 写 Looi 也 ack，但 motor 不会动 — 推测 Looi 用 write-type 区分 "keep-alive ack" vs "motor command".

### 2c. Head (FED1) — pitch（不是 yaw）

**关键修正：FED1 控制的是 head PITCH（俯仰/抬低头），不是 yaw（水平转向）。** Looi 的水平转向通过 FED0 movement 的 turn 字节实现（轮子原地 spin）。

| 命令 | bytes | 实测 |
|---|---|---|
| center | `5A` | ✅ 头回中 |
| look up step | `64` from center | ✅/⚠️ novolei/LOOI-Robot 从 `5A` 每次 `+0A` |
| look down step | `50` from center | ✅/⚠️ novolei/LOOI-Robot 从 `5A` 每次 `-0A` |
| extrema | `00` / `FF` | ⚠️ 极限值不应用作 DevTools 普通按钮；真实体验可能触发机械回弹或固件保护 |

单次写即可，**不需要 heartbeat**。

**Open questions：**
- `0x00` / `0xFF` 极限值的固件/机械保护行为仍需系统记录。
- 其它中间值（如 `0x30` `0x80`）是 hold position 还是 gesture？
- 是否有"head yaw"通过其它 char 控制（之前假设的 left/right 实际不存在；如果 Looi 真的有头部水平摇摆，可能是别的 char）

### 2d. Light (FED2)

| 命令 | bytes | 实测 |
|---|---|---|
| off | `00` | ✅ 灭 |
| 其它 1-byte 值 | `01`..`7F` | ✅ **亮度梯度**（不是 on/off binary）；`7F` 是当前可靠最大可见值 |
| app full | `7F` | ✅ Ryan 2026-05-19 真机反馈推导：旧 Half 实际发 `7F` 且有效，`FE/FF` 不亮 |
| high unsigned range | `80`..`FF` | ⚠️ 暂视为保留/不可靠值；不要用于普通亮度 UI |

**重要差异：** sooper README 写 "Direct control: `00`=Off, `03`=On"，但实测**是连续 PWM analog 亮度**，不是 binary。M1 LightController API 应暴露 `setBrightness(_:UInt8)` 而不是 `setOn(_:Bool)`。

### 2e. Rich (FE00) ❓

未实测。sooper README 示例 17 byte：
`00 07 00 FF 05 00 00 00 00 64 02 0A 96 02 14 00 02`

每个 byte field 含义（per sooper）：`[SEQ] [OPCODE] [SUB_OP] [MASK_A] [MASK_B] [PAYLOAD 4 bytes] [VALUE] [PARAM 2 bytes] [DURATION] [PARAM 2 bytes] [RES] [END/CRC]`。Opcode 表未知（不在 sooper README 里），完整 reverse engineering 需要 sniff 官方 app traffic。**留给 M3 lipsync coordinator 用**（如果届时确实需要协调 motor + light + screen 动画再做）。

### 2f. FF02 boost motor ❌

写 `7F 00` 实测**无任何反应**。FF02 在本台 Looi 上不是替代 motor 通道。可能：
- sooper 测试的 Looi 是不同型号
- FF02 需要不同的 byte 格式 / 长度
- FF02 是只读但 props 误报为 write-able

**LooiKit 不应暴露 FF02 作为公开 API**，至多 M1 spec 里列为"未来探测项"。

---

## 3. FED9 传感器流解码 ⭐

**核心发现：FED9 是 multiplexed sensor stream**，第 0 字节是 packet type ID，不同 type 不同 payload。这点 sooper README 没提（只说 "Cliff sensors, TOF distance, Battery"，没说包结构）。

| Type ID | Total length | Payload format | 含义 | 触发条件 |
|---|---|---|---|---|
| `0x11 0x01 0x00` | 3 bytes | fixed | **Boot/init status complete** | 仅 INIT 握手完成时**一次** |
| `0x01 [b1] [b2] [b3] [b4]` | 5 bytes | 4 binary states | **二值传感器状态**（cliff / 触地等） | 持续推送，状态变化时 |
| `0x02 [b1] [b2]` | 3 bytes | signed int16 (little-endian 推测) | **IMU 类轴向读数**（accelerometer / gyro / encoder） | 运动 / 倾斜 / 触摸时 |
| `0x09 [b1]` | 2 bytes | 0/1 boolean | **触摸事件**（按下 / 释放） | 触摸机身侧面时 |

### 3a. Cliff sensor mapping (packet type `0x01`)

部分映射（基于本次抬升测试）：

| 物理状态 | 5-byte payload | 推断 |
|---|---|---|
| 4 轮全部接地 | `01 01 01 01 01` (occasional) | 全部 1 = 全接地 |
| 全悬空 | `01 01 01 01 00` 或 `01 01 01 00 00` | 反直觉：byte 1-3 仍为 1，byte 4 / 3 转 0 |
| 抬起前端 | `01 00 01 01 01` ↔ `01 01 01 01 01` 切换 | **byte 1 = 前端 cliff** ✅ |
| 抬起后端 | `01 01 01 01 0X`（无清晰 0 切换）| 后端 cliff byte 不明，可能是 b4 但未隔离 |
| 抬左 / 抬右 | 未隔离测 | 待 M1 期间补 |

**已知未完成：** byte 2/3/4 ↔ 后/左/右物理映射。M1 时再补，需要把 Looi 在桌沿一次只挂一个轮做隔离测试。

### 3b. Type `0x02` IMU 类数据

样本：`02 ff f8`、`02 ff f2`、`02 ff fd`、`02 ff ff`、`02 f4 ff`、`02 ee fe`

- `ff f8` 当 int16 little-endian = `0xf8ff` = -1793（unlikely magnitude）
- `ff f8` 当 int16 big-endian = `0xfff8` = -8 signed（合理 accelerometer-like 值）
- 触摸 / 倾斜 / 运动时频繁出现，static 时少
- 推测：IMU 单轴向量 magnitude，big-endian signed int16

未确定：是 accelerometer 还是 gyro；x/y/z 哪一轴；单 packet 一轴还是合成。M1 需要：在固定姿态下采样 baseline → 加速度 +X 方向看哪个 byte 变化。

### 3c. Type `0x09` 触摸事件

实测：摸机身左右侧时出现 `09 01` → `09 00` → `09 01` 循环（按下 → 释放 → 再按）。

未确定：是否区分左 / 右 / 多 zone？仅 1-byte payload，可能用值区分（如左 = 0x01，右 = 0x02）。M1 期间用更精细的触摸方式测。

---

## 4. M1 LooiKit 设计含义

把 M0.5 的发现翻译成 M1 spec 应该有的 API：

### 4a. `LooiSession` —— lifecycle wrapper

```swift
@MainActor @Observable
final class LooiSession {
    enum State { case idle, connecting, handshaking, ready, disconnected(Error?) }
    var state: State

    func connect() async throws       // includes 2A29 read + 5-step INIT + start keep-alives
    func disconnect()                 // sends safety STOP + cancels keep-alives + cleans up
    func forgetPairing()
}
```

`LooiSession` 应该把 BLE 状态机封装到一个 actor 内部，对外只暴露干净的 `state` 流，避免散落的 keep-alive task 管理。

### 4b. 4 个 controller protocol

```swift
protocol MotionController {
    func setMotion(speed: Int8, turn: Int8)   // internal heartbeat picks this up @ 30ms
    func stop()
    // optional convenience
    func forward(_ intensity: Double)         // 0...1 → 0..127
    func spin(_ intensity: Double)            // -1..1 → -127..+127
}

protocol HeadController {
    func setAngle(_ value: UInt8)             // single write FED1
    func center()
    func offset(degrees: Int)                 // approx 10°/unit
}

protocol LightController {
    func setBrightness(_ value: UInt8)        // 1-byte FED2 analog gradient
    func off()
    func on()                                  // = setBrightness(0x7F)
}

protocol SensorStream {
    var cliffEvents: AsyncStream<CliffEvent>  { get }   // type 0x01 decoded
    var touchEvents: AsyncStream<TouchEvent>  { get }   // type 0x09 decoded
    var motionData: AsyncStream<MotionSample> { get }   // type 0x02 decoded
    var bootStatus: AsyncStream<BootStatus>   { get }   // type 0x11 decoded
}
```

### 4c. Safety — Cliff handling

`LooiSession` 应暴露 `groundedState: AsyncStream<GroundedState>`，由 SensorStream 的 cliff 流派生。
- 选项 A：`MotionController` 内部硬阻断 — 不接地时 setMotion no-op
- 选项 B：让 app 层决定 — 仅暴露状态，UI 决定是否在 cliff 时禁用驱动按钮（参考 M0.5 ConnectionBanner 模式）

**M1 spec 应明确选 A 或 B**（推荐 A，提供更强安全保障；M1 可附加"override"逃生孔给特殊场景）。

### 4d. Keep-alive 抽象

`LooiSession.connect()` 内部启动两个并行 task：
- Motor heartbeat：30ms 间隔，`.withoutResponse`，写当前 `MotionController` 状态到 FED0
- Battery poll：4s 间隔，read FED8，更新 `LooiSession.batteryLevel`

`disconnect()` 取消两个 task + 显式写 STOP 到 FED0（已在 M0.5 BLECentral.disconnect 实现）+ reset motion state。

### 4e. 配对持久化

UserDefaults wrapper 或者更结构化的 `PairingStore` —— 保存最后成功 INIT 的 peripheral UUID + 设备名。auto-reconnect 用同样的 scan-fallback 模式（M0.5 已验证）。

### 4f. 错误恢复

- direct connect 5s 超时 → scan fallback 15s
- 失败 → `abandonPendingConnection()` 清空状态
- iOS BLE state 变化 → state machine 重新评估
- 这些 M0.5 都验证过，M1 直接搬过来

---

## 5. 已知未解（M1 / 后续里程碑处理）

### 高优先（M1 期间应该完成）

- [ ] FED9 type `0x01` byte 2/3/4 ↔ 后 / 左 / 右 cliff sensor 物理映射（需要桌沿单轮隔离测试）
- [ ] FED9 type `0x02` IMU 数据语义（axis、单位、是否 signed big-endian int16）
- [ ] FED9 type `0x09` 触摸事件 zone 区分（左 vs 右 vs 其它）
- [ ] FED2 light 亮度梯度精确曲线（值 → lumens 或人眼感知亮度）
- [ ] FED8 battery 第 2 个 byte 含义（status flag 含义：充电中？低电？）

### 中优先（M1-M2 期间）

- [ ] FED5 sensor stream 内容（INIT 时 subscribe 但未观察到 packets，需要某种 actuator 状态触发）
- [ ] FED3 / FED6 / FED7 / FEDF / FED4 / FEF0 功能（write-only 的可以盲探，notify 的需要找到触发条件）
- [ ] 8018 service 4 个 chars 功能（猜测固件 OTA 或鉴权 token；M0.5 没碰）
- [ ] iOS 后台 BLE 行为（app 进入后台时 heartbeat 是否存活；M5 reflex layer 需要）

### 低优先（M3+ 真要 lipsync / 动画时再做）

- [ ] FE00 17-byte rich command opcode 表（需要 sniff 官方 app traffic）
- [ ] FF02 boost motor 是否对其它 Looi 型号有效（如果只有本台不响应可能是 model variant）

---

## 6. 时间日志

| 日期 | 进度 |
|---|---|
| 2026-05-17 上午 | M0.5 scaffold 完成；ulooi.xcodeproj 完成；LooiKit/LooiProtocol/LooiCommand 初始合并 |
| 2026-05-17 下午 | OSLog 探针 → 修 Form 多按钮 trap → didDiscover 节流 → auto-init → motor heartbeat → battery poll → adaptive polling → scan-fallback → cleanup → motion state machine → cliff sensor 反向工程 |
| 2026-05-17 晚 | 当前文档整理 |

**净有效时间：** ~1 整天（密集 iterative debug）。
**远超原 plan「1-2 天 throwaway」**，但**深度也远超** —— 不只验证了 ref repo 的命令字典，还反向工程了 FED9 多 packet type、cliff safety 机制、battery format、handshake 时序、`.withResponse` vs `.withoutResponse` 的语义区分。

---

## 7. 关键代码 commit 引用（用于 M1 spec 参考实现）

| Commit | 内容 |
|---|---|
| `687c5ec` | M0.5 BLE probe scaffold（DevTools 5-tab + LooiKit skeleton）|
| `90c51a1` | 初始 Looi protocol 综合（andrey-tut + sooper）|
| `17bc78a` | Form 多按钮 single-tap target trap 修复（关键 SwiftUI 教训）|
| `38519fe` | OSLog 探针（DevLog triple channel + watermark）— 没有这个无法定位多个 silent failure |
| `cb1c7a9` | `nonisolated` for translate（Swift 6 strict mode 第 1 个 trap）|
| `746cbdb` | `nonisolated` for static let（Swift 6 strict mode 第 2 个 trap）|
| `4f53930` | `abandonPendingConnection` 清空 dangling reference 避免假连接 UI |
| `4ee45c4` | adaptive connect / discover polling（替代固定 sleep）|
| `6e7b32e` | `.withoutResponse` for motor（match Python，关键发现）|
| `6fac162` | scan-fallback 重连路径 + offline-disable motion buttons |
| `5e60b37` | 2A29 wake-up + FED8 battery poll（match 完整 waasd.py keep-alive）|
| `668add7` | auto-reconnect 持久化 paired peripheral UUID |
| `d4cbe9f` | heartbeat-aware motion state + safety STOP on disconnect |
| `21e85c1` | PresetRow tap reliability + DevLog preset clicks |

---

## 8. 迁移清单 → M1 spec

写 M1 spec 时把以下条目逐个搬入：

- [ ] §1 GATT 拓扑 → M1 spec "§2 LooiKit char dictionary"，标 ✅/⚠️/❓
- [ ] §2a Handshake → M1 spec "LooiSession.connect() 实现"
- [ ] §2b-d Movement/Head/Light → M1 spec "MotionController / HeadController / LightController API"
- [ ] §3 FED9 packet type → M1 spec "SensorStream 多 packet type dispatch decoder"
- [ ] §4 LooiKit 设计含义 → M1 spec 各模块设计章节
- [ ] §5 已知未解 → M1 spec "§N risks & open questions"
- [ ] §7 commit 引用 → M1 spec 实现章节作为 reference
- [ ] cliff safety 决策（A 硬阻断 vs B 仅暴露状态）→ M1 brainstorm 需要决议
- [ ] keep-alive 任务管理策略（@MainActor Task 还是独立 actor）→ M1 brainstorm 需要决议

---

**M0.5 status：DONE_WITH_CONCERNS** —— 核心目标全部达成；列出的 known-unknowns 在 M1 期间随时可补，不阻塞 M1 spec 撰写。
