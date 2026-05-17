# M0.5 Prototype Findings

**起：** 2026-05-17
**止：** _(填写)_
**硬件：** _(Looi model / serial / 包装上标识)_
**固件版本：** _(从 GATT Device Information service 读取，或 inspect 推断)_
**iOS 测试设备：** _(iPhone model + iOS version)_

> 此文档伴随 M0.5 probe 同步演化。完成时整合归档，成为 M1 LooiKit spec 的 §2 输入。
> "验证"指：probe app 实测重复成功 ≥ 3 次。
>
> 协议假设来自两个 ref repo 的综合（详见 `ulooi/ulooi/LooiKit/LooiProtocol.swift`）；下面的表预填了
> 综合后的预期值，你只需把"实测"列填上 ✅ / ❌ / ⚠️。

---

## 0. 操作流程（每次上电）

1. 开 Xcode → `xed ulooi.xcodeproj` → Cmd+R → iPhone
2. App 启动 → 默认进 DevTools → Scan tab
3. **Start Scan** → 等"LOOI"开头的设备出现（按 RSSI 排序）
4. **Connect** → Inspect tab → **Discover all services**
5. **Copy topology as JSON** → 粘到下面 §1
6. Command tab → 按顺序点：
   1. **INIT 1/2** —— 写 0x01 到 FEDA
   2. **回 Sense tab** —— 订阅 FED5 和 FED9（toggle on）
   3. 回 Command tab → **INIT 2/2** —— 写 0x03 到 FEDA
7. （此时机器人应已 ready）依次试 STOP / Forward / Backward / Head center / Light on …，每条对照下面表格填 §2

---

## 1. GATT 拓扑（实测）

通过 Inspect → Copy topology as JSON 拿到的实测结构：

```
(粘贴 InspectView 的 Copy 输出)
```

### 1a. UUID 表对照（综合 ref → 实测）

| 短 UUID | ref 标记的功能 | 实际发现？ | properties (实测) | 备注 |
|---|---|---|---|---|
| FED0 | Movement (write)              | ☐ | _read/write/notify_ | |
| FED1 | Head (write)                  | ☐ | | |
| FED2 | Light/torch (write) ⚠️         | ☐ | | sooperchargeforbots only |
| FED5 | Sensors (notify)              | ☐ | | |
| FED8 | Battery (read)                | ☐ | | |
| FED9 | Telemetry (notify)            | ☐ | | cliff/TOF/battery stream |
| FEDA | Handshake/settings (write)    | ☐ | | required for init |
| FE00 | Rich command (write 17-byte) ❓| ☐ | | sooperchargeforbots, exploratory |
| FF02 | Motor boost (write)           | ☐ | | sooperchargeforbots, exploratory |
| 2A29 | Manufacturer name (read)      | ☐ | | GATT standard; macOS warm-up |

### 1b. 未在 ref 中出现但实测发现的 services / characteristics

| UUID | properties | 推测用途 |
|---|---|---|
| _(填)_ | | |

---

## 2. 命令验证（综合 ref → 实测）

### 2a. Handshake（必须成功否则后面全无响应）

| 步骤 | UUID | bytes | 实测 |
|---|---|---|---|
| read | 2A29 | — | ☐ ✅ / ☐ ❌ |
| write | FEDA | `01` | ☐ |
| notify | FED5 | (subscribe) | ☐ |
| notify | FED9 | (subscribe) | ☐ |
| write | FEDA | `03` | ☐ |

握手后机器人是否有任何"我准备好了"的物理/灯光信号？_(描述)_

### 2b. Movement (FED0)

| 命令 | bytes | 预期行为 | 实测 | 备注 |
|---|---|---|---|---|
| stop | `00 00` | 停 | | |
| forward max | `7F 00` | 全速前进 | | 心跳 30ms |
| backward max | `81 00` | 全速后退 | | |
| spin left | `00 7F` | 原地左转 | | |
| spin right | `00 81` | 原地右转 | | |
| mixed | `40 40` | 半速 + 半左 | | |

**心跳验证：** 发一次 `7F 00` 然后停止 —— 机器人多久停下？预期 ~30ms 后失活。

| 实测停止时间 | _(ms)_ |
|---|---|

### 2c. Head (FED1)

| 命令 | bytes | 预期 | 实测 | 备注 |
|---|---|---|---|---|
| center | `5A` | 90° | | |
| full left | `00` | min | | |
| full right | `FF` | max | | |
| +10° | `64` | 微右 | | |
| -10° | `50` | 微左 | | |

### 2d. Light (FED2) ⚠️

| 命令 | bytes | 预期 | 实测 | 备注 |
|---|---|---|---|---|
| off | `00` | 灯灭 | | |
| on | `03` | 灯亮 | | |
| ? | `01` | _(未知)_ | | 试一下 |
| ? | `02` | _(未知)_ | | 试一下 |
| ? | `04`..`FF` | _(扫描)_ | | 是否有亮度梯度？RGB？|

### 2e. Rich 17-byte (FE00) ❓

| 命令 | bytes | 实测 |
|---|---|---|
| sooper README example | `00 07 00 FF 05 00 00 00 00 64 02 0A 96 02 14 00 02` | _(描述发生了什么)_ |

不期待全懂，记录任何观察到的反应即可。

---

## 3. 传感事件解码（FED5 + FED9 notify）

订阅后做物理动作，记录 byte 流。

### 3a. FED5 (sensors — 推测 touch)

| 物理动作 | bytes (hex) | 频率 | 持续 |
|---|---|---|---|
| 摸头顶 | | | |
| 摸下巴 | | | |
| 摸背部 | | | |
| 不动（baseline） | | | |

### 3b. FED9 (telemetry — cliff / TOF / battery)

| 触发 | bytes (hex) | 备注 |
|---|---|---|
| 端起放下（cliff?） | | |
| 前方放手（TOF?） | | |
| baseline 5s | | |
| 低电量（如能复现） | | |

### 3c. FED8 (battery read)

| 时刻 | 读到的 bytes | 推断电量 % |
|---|---|---|
| 满电 | | |
| 半电 | | |
| 低电 | | |

---

## 4. M1 LooiKit 设计含义

prototype 反过来要怎么影响 M1 spec？逐条记录：

- _(e.g. "MotionController.start() 需自动起一个 30ms heartbeat task；显式 stop 才退出")_
- _(e.g. "FED2 实测只有 on/off — 不要在 LightController 暴露 setBrightness(_:Float)，改成 setOn(_:Bool)")_
- _(e.g. "SensorStream.touches 需要 debounce — 摸一下会触发 N 个 byte，相邻 X ms 内视为同一次")_
- _(e.g. "Init handshake 必须在 connect 完成 + 服务发现完成后自动跑；LooiSession.bringUp() 封装")_
- _(e.g. "BLE 命令 RTT 中位数 X ms / p95 Y ms — lipsync coordinator 节拍计算用这个")_

---

## 5. 已知未解（M1 / M2 处理）

- _(e.g. "FE00 17-byte 包的 opcode 表未知 —— 要 sniff 官方 app 流量才能完整反解。M3 视情况推进。")_
- _(e.g. "BLE 连接偶尔在 iOS 锁屏 30s 后掉 —— background mode 配置 M3 处理。")_
- _(e.g. "Light 命令所有候选值都无响应 —— 是否硬件不带灯？或要其它握手？")_

---

## 6. 时间日志

| 日期 | 进度 | 卡点 |
|---|---|---|
| 2026-05-17 | scaffold 完成（DevTools 五屏 + LooiProtocol/LooiCommand 含综合后的 ref 字节序列） | 待上机 |
| _(下一日填)_ | | |

---

## 7. 整合 → M1 spec 时的迁移清单

完成 M0.5 后这里列出要带去 M1 spec 的具体条目：

- [ ] §1 GATT 拓扑 → M1 spec §2 "LooiKit 命令字典 — verified UUIDs"
- [ ] §2 命令验证表 → M1 spec §2 "命令字典 — verified bytes"
- [ ] §3 传感事件 → M1 spec "SensorStream 解码器" 设计
- [ ] §4 M1 设计含义 → M1 spec 各章节"prototype-driven decisions"
- [ ] §5 已知未解 → M1 spec §7 "风险与开放问题"
