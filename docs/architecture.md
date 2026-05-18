# ulooi 总体框架设计（Architecture）

**日期：** 2026-05-17
**版本：** v0.1 — 初版，对应 M0 umbrella spec
**关联文档：**
- [M0 umbrella spec](https://github.com/novolei/uclaw-new/blob/main/docs/superpowers/specs/2026-05-17-ulooi-design.md)（程序级设计，含跨项目协议）
- [PRD `prd.md`](./prd.md)（产品视角）

---

## 0. 当前代码真相（2026-05-18）

本文档描述的是目标架构 + 当前实现的对照。当前仓库已经完成 **M1 PR1 LooiKit foundation**，但还没有进入 UCLAW transport / voice / reflex / production face shell。

已实现：

- `Packages/LooiKit` Swift Package：`LooiSession`、`BLETransport`、`CoreBluetoothTransport`、`MockBLETransport`、`HandshakeRunner`、`SessionStateMachine`、`ReconnectPolicy`、Motion/Head/Light/Sensor controllers、typed command bytes、LooiKit unit tests。
- `ulooi` app target：`ContentView` 仍然进入 DevTools；`LooiBootstrap` 创建共享 `CoreBluetoothTransport + LooiSession` 并做 cold-launch auto-reconnect；DevTools tabs 已经通过 LooiSession/controllers 操作硬件。
- M0.5 真机结论已进入实现：FEDA handshake、FED0 30ms `.withoutResponse` heartbeat、FED1 pitch、FED2 brightness、FED8 4s battery poll、FED9 telemetry subscription。M1.2 DevTools 真机修正：FED1 从中心 `0x5A` 追踪 pitch，写入使用 `.withoutResponse`；DevTools label-wise Look Up 向更小 byte 步进，Look Down 向更大 byte 步进，步进 `0x20`；FED2 app-level full 使用 signed positive max `0x7F`，避开不可靠的 `0x80...0xFF`。

未实现：

- `Modules/Transport` 中的 CBOR-over-WebSocket、mDNS/Tailscale discovery、QR pairing、TLS pinning。
- `Modules/Sensory` / `Modules/Reflex` / `Storage`。
- CDDL schema codegen pipeline 与 UCLAW Rust 端同步。
- Production Onboarding/Home/Conversation/Privacy/Settings，以及 Face Engine / GestureLibrary。

Repo 边界：

- `ulooi` repo: `/Users/ryanliu/Documents/uclaw/ulooi`
- 对应 UCLAW workspace/repo family: `/Users/ryanliu/Documents/uclaw`
- 两者单独管理 git；branch、commit、PR、status 不共享。任何跨端改动都必须显式说明分别落在哪个 repo。

## 1. 架构总览

```
┌─────────────────────────────────────────────────────────────────┐
│                         iPhone (iOS 18.2+)                       │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │  UI Layer (SwiftUI)                                        │ │
│  │  · Views · Navigation · Theming · Accessibility            │ │
│  └────────────────────────┬───────────────────────────────────┘ │
│                           │                                      │
│  ┌────────────────────────┴───────────────────────────────────┐ │
│  │  App State (Observable + Swift Concurrency)                │ │
│  │  · ConnectionState · ConversationState · DegradationState  │ │
│  └────────┬────────────────┬─────────────────┬────────────────┘ │
│           │                │                 │                   │
│  ┌────────┴────┐  ┌────────┴────────┐  ┌────┴──────────────┐    │
│  │  SENSORY    │  │  REFLEX         │  │  TRANSPORT        │    │
│  │  · Mic ASR  │  │  · State Machine│  │  · CBOR codec     │    │
│  │  · Camera   │  │  · Offline Queue│  │  · WebSocket Cli  │    │
│  │  · TTS      │  │  · Foundation   │  │  · mDNS Discovery │    │
│  │  · Wake     │  │    Model        │  │  · Tailscale det  │    │
│  │  · VAD      │  │  · Lipsync      │  │  · TLS pinning    │    │
│  │             │  │    Coordinator  │  │                   │    │
│  └─────────────┘  └────────┬────────┘  └────────┬──────────┘    │
│                            │                    │                │
│  ┌─────────────────────────┴──────────┐  ┌──────┴───────────┐   │
│  │  LooiKit (Swift Package, in-tree)  │  │  Persistence     │   │
│  │  · LooiDevice · MotionController   │  │  (GRDB / SQLite) │   │
│  │  · LightController · SensorStream  │  │  · WAL queue     │   │
│  │  · BLE transport (CoreBluetooth)   │  │  · Pair tokens   │   │
│  └──────────────────┬─────────────────┘  │    (Keychain)    │   │
│                     │                    └──────────────────┘   │
└─────────────────────┼───────────────────────────────────────────┘
                      │ BLE (CoreBluetooth, no audio)
                ┌─────┴─────┐
                │   LOOI    │ (motion / light / touch / battery)
                └───────────┘

           ──── network ──── CBOR over WSS ─────
                                │
                ┌───────────────┴───────────────┐
                │  UCLAW Desktop                │
                │  RemoteBridgeService (M2 新增)│
                └───────────────────────────────┘
```

---

## 2. 技术栈选择

### 决定：Pure SwiftUI / Swift（含一致性 codegen，无 Rust on iOS）

**Rationale：**

1. **Apple Foundation Model 只有 Swift binding** —— reflex 层离线推理是 P0，必须从 Swift 调，再加 Rust 层只是绕一圈。
2. **AVFoundation / Speech / CoreBluetooth 都 Swift-native** —— ulooi 的 IO 90% 是 Apple 框架。
3. **Reflex 层逻辑量小** —— 状态机、offline queue、intent 分类器加起来 < 2000 行，Swift Concurrency + actor 完全胜任，不需要 Rust 的"系统级性能"。
4. **避免 cargo + xcframework + uniffi 的构建复杂度** —— iOS-only 项目，单一 Xcode 工具链最干净。
5. **协议一致性靠 schema codegen** —— wire envelope schema 定义在 CDDL（[RFC 8610](https://datatracker.ietf.org/doc/html/rfc8610)），用 build 阶段脚本同时生成 Swift `Codable` 类型和 Rust serde 结构，两端类型从单一源派生。

### 显式拒绝的方案

| 方案 | 拒绝原因 |
|---|---|
| 完整 `uclaw_core` 移植到 iOS（M0 spec Option C） | Python（memU bridge）不能在 iOS 沙盒跑；Provider key 多端同步是另一个项目；6 个月起范围 |
| SwiftUI + Rust core via uniffi | FFI 复杂度大于收益；Foundation Model 仍要 Swift 侧持有；调试体验差 |
| Hybrid Rust crate 只放 CBOR codec | 同样的协议一致性收益用 CDDL codegen 可达成，FFI 表面积更大 |
| Flutter / React Native / Cross-platform | 放弃 Foundation Model、AVAudioSession 精细控制、CoreBluetooth 后台 mode |

### 关键工具与版本

| 类别 | 选择 | 备注 |
|---|---|---|
| 语言 | Swift 6.x | strict concurrency；当前 `Packages/LooiKit/Package.swift` 使用 Swift tools 6.2 / language mode v6 |
| UI | SwiftUI（iOS 18+ API） | 不引入 UIKit 桥；纯 SwiftUI |
| 异步 | Swift Concurrency（async/await + actor） | 不用 Combine，不用 RxSwift |
| 持久化 | [GRDB](https://github.com/groue/GRDB.swift) | SQLite WAL queue + 元数据；Apple SQLite 太底层 |
| BLE | CoreBluetooth（直接，无第三方封装） | 在 LooiKit 内部包装 |
| Audio | AVFoundation + AVSpeechSynthesizer | + 可选 ElevenLabs streaming 提质 |
| ASR | Speech.framework（`SFSpeechRecognizer`） | on-device only mode |
| LLM (reflex) | Apple Foundation Models framework（iOS 18.2+） | 仅黄段降级使用 |
| WebSocket | [URLSessionWebSocketTask](https://developer.apple.com/documentation/foundation/urlsessionwebsockettask) | iOS 原生，不引第三方 |
| CBOR | [SwiftCBOR](https://github.com/valpackett/SwiftCBOR) 或 [PotentCodables](https://github.com/outfoxx/PotentCodables) | 选定见下文模块设计 |
| mDNS | [Network.framework](https://developer.apple.com/documentation/network) `NWBrowser` | 原生 |
| QR | AVFoundation `AVCaptureMetadataOutput` | 原生 |
| Crypto | [CryptoKit](https://developer.apple.com/documentation/cryptokit) | ed25519 签名、TLS pinning |
| Schema codegen | 自研 build script + [zcbor](https://github.com/NordicSemiconductor/zcbor) 或 [cddl-codegen](https://github.com/dcSpark/cddl-codegen) | 见 §6 |
| 测试 | XCTest + [Swift Testing](https://developer.apple.com/xcode/swift-testing/)（iOS 18+） | 单元 + UI 测试 |

### 不引入的依赖

- 任何 Reactive 流（Combine / RxSwift）—— Swift Concurrency 足够
- 任何 DI 框架 —— SwiftUI environment + 显式注入足够
- 任何"all-in-one"BLE 库 —— CoreBluetooth 直接用更可控

---

## 3. 模块分层

四层（自下而上）：

| 层 | 职责 | 不允许 |
|---|---|---|
| **LooiKit** | 跟 Looi 硬件的 BLE 抽象（motion / light / sensor） | 不知道 UCLAW、不知道用户、不持有应用状态 |
| **Transport** | 跟 UCLAW 的 CBOR-over-WSS 通信，配对，发现 | 不解释业务事件、不持有 UI |
| **REFLEX + SENSORY** | 业务逻辑：状态机、降级、音视频 IO、本地推理、lipsync | 不直接操作 BLE 或 socket（走 LooiKit / Transport） |
| **UI** | SwiftUI views、navigation、theming、a11y | 不直接调底层；只观察 App State |

**依赖方向严格向下**：UI 看到 App State，App State 协调 REFLEX/SENSORY，后者使用 LooiKit/Transport。LooiKit 和 Transport 互不知道。这让单元测试可以替换上层。

---

## 4. 模块详述

### 4.1 LooiKit（Swift Package, in-tree at `Packages/LooiKit/`）

**单一职责：** 把 Looi 机器人变成一个有类型的 Swift 对象。

当前 public handle 是 `@MainActor @Observable final class LooiSession`，不是早期草案里的 `LooiDevice` protocol。`LooiSession` 持有：

- `state: SessionState`
- `currentPeripheral: DiscoveredPeripheral?`
- `motion: MotionController`
- `head: HeadController`
- `light: LightController`
- `sensor: SensorController`
- `pairedPeripheralID`（UserDefaults 持久化）
- `reconnectPolicy`

核心流程：

```text
scan/connect
  -> discoverServicesAndCharacteristics
  -> HandshakeRunner:
       read 2A29
       write FEDA 0x01
       subscribe FED5 + FED9
       sleep 300ms
       write FEDA 0x03
  -> SensorController.consume(FED5, FED9)
  -> .ready
  -> MotionController.startHeartbeat()
  -> SensorController.startBatteryPoll()
```

**内部结构：**

```
Packages/LooiKit/Sources/LooiKit/
├── LooiKit.swift
├── Protocol/
│   ├── LooiProtocol.swift          # CBUUID constants, timing, FEDA bytes
│   ├── HandshakeRunner.swift       # typed 2A29/FEDA/FED5/FED9 init sequence
│   └── HandshakeStep.swift
├── Transport/
│   ├── BLETransport.swift          # test seam
│   ├── CoreBluetoothTransport.swift
│   ├── DiscoveredPeripheral.swift
│   └── WriteType.swift
├── Session/
│   ├── LooiSession.swift
│   ├── SessionState.swift
│   ├── SessionStateMachine.swift
│   └── ReconnectPolicy.swift
├── Controllers/
│   ├── MotionController.swift      # FED0 30ms heartbeat + cliff hard-block
│   ├── HeadController.swift        # FED1 pitch
│   ├── LightController.swift       # FED2 brightness
│   └── SensorController.swift      # FED5/FED9 decode + FED8 poll
├── Commands/
│   ├── LooiCommand*.swift          # movement/head/light/handshake/rich bytes
├── Models/
│   ├── MotionState.swift
│   ├── CliffState.swift
│   └── CharacteristicProperties.swift
├── Errors/
│   └── LooiError.swift
└── Util/
    ├── DataHexCodec.swift
    └── ComparableClamped.swift

Packages/LooiKit/Sources/LooiKitTesting/
├── MockBLETransport.swift
├── FakeClock.swift
└── LooiKitTesting.swift
```

**当前测试策略：** `MockBLETransport` 注入 `LooiSession` / controllers，覆盖 command bytes、handshake、session transitions、heartbeat、sensor decode、battery poll、reconnect policy。尚未建立真实 `.bleskel` replay fixture；这是下一步补齐传感器语义的关键。

### 4.2 SENSORY（音视频 IO）

`Modules/Sensory/`：

| 子模块 | 职责 |
|---|---|
| `WakeWordDetector` | 持续监听 "Hey Looi"（或可配置），触发 `wakeDetected` 事件 |
| `VoiceCapture` | VAD + streaming ASR（Apple Speech, on-device），产 `voicePartial` / `voiceFinal` |
| `Speaker` | TTS 流式播放；默认 AVSpeechSynthesizer，可切 ElevenLabs；暴露 `playbackProgress` |
| `CameraCapture` | 触发条件下激活，抓帧；隐私提示协调（红→绿过渡） |

**SENSORY 与 REFLEX 的契约：** SENSORY 暴露 `AsyncStream` 给 REFLEX 订阅；REFLEX 决定是否往 Transport 推。SENSORY 不直接发 WebSocket。

### 4.3 REFLEX

`Modules/Reflex/`：

| 子模块 | 职责 |
|---|---|
| `ConnectionStateMachine` | 绿/黄/红 状态判定 + 转换；ping/pong 5s；BLE RSSI 观察 |
| `OfflineQueue` | GRDB 持久 envelope WAL；恢复时按 `id` 顺序 replay |
| `FoundationModelDriver` | 黄段触发；包装 Apple Foundation Models framework；prompt 模板（"你是离线的 Looi，能基础对话，复杂问题诚实拒答"） |
| `IntentRouter` | 用户输入到达时决定"reflex 能答 / 必须 cortex"；reflex-answerable 集合静态白名单 + Foundation Model 二次判定 |
| `LipsyncCoordinator` | 订阅 `Speaker.playbackProgress`，节拍化为 `LightController.pulse` + 微动作 |

**LipsyncCoordinator 算法（M3 prototype 确定细节）：**

```
input:  TTS audio chunks (with timing metadata: chunk → start_ms, duration_ms)
output: BLE light_pulse commands at envelope-amplitude beats

step 1: 估算每个 chunk 的 envelope amplitude (peak detection on PCM)
step 2: amplitude > threshold → 触发一个 light pulse
step 3: 同时 schedule 一个 motion_micro（头部小幅前倾 5°）
step 4: 整段 TTS 结束 → 灯光恢复 idle、头部回中
```

延迟预算：BLE 命令 round-trip ~30ms → 必须在 TTS chunk 播放前 ~50ms 发出。

### 4.4 TRANSPORT

`Modules/Transport/`：

| 子模块 | 职责 |
|---|---|
| `Envelope` | CBOR 编解码（包含 ULID 生成、wall clock、kind 命名空间约定） |
| `EventBus` | typed pub/sub —— 业务订阅 `voice.partial` 不需要 deal CBOR |
| `WebSocketClient` | URLSessionWebSocketTask 包装；自动重连；ping/pong |
| `Discovery` | NWBrowser mDNS + Tailscale ip 探测；返回候选 host 列表 |
| `Pairing` | QR 解码、ed25519 keypair 生成、握手、token 持久化（Keychain）、滚动续期 |

**重要：** Transport 不知道任何业务事件含义。`EventBus.publish(envelope)` 后由 REFLEX/SENSORY 注册的 handler 处理。这让协议层与业务解耦，新事件类型只需注册 handler。

**当前状态：** 该层尚未实现。当前仓库里的 `Transport/` 指的是 LooiKit 内部 BLE transport seam，不是 UCLAW network transport。命名上要避免混淆：

- `Packages/LooiKit/Sources/LooiKit/Transport` = BLE transport abstraction
- 未来 `ulooi/Modules/Transport` = UCLAW CBOR-over-WebSocket transport

### 4.5 App State

`App/State/` —— 整个 app 的 single source of truth（`@Observable` macro）：

```swift
@Observable
final class AppState {
    // 设备层
    var pairedLooi: PairedLooi?
    var looiConnection: LooiConnectionState  // searching / connected / error
    var battery: LooiBattery?

    // UCLAW 层
    var pairedUclaw: PairedUclaw?
    var uclawConnection: UclawConnectionState
    var degradation: DegradationState  // green / yellow / red

    // 会话层
    var currentConversation: ConversationState
    var voiceActivity: VoiceActivity  // idle / userSpeaking / agentSpeaking
    var lastError: AppError?

    // 用户偏好
    var settings: UserSettings  // pause mic, voice provider, etc.
}
```

UI 通过 SwiftUI environment 拿到 `AppState`；views 用 `@Bindable` 或 read-only 观察。

### 4.6 UI 层

`Views/`：

| 文件 | 职责 |
|---|---|
| `ContentView.swift` | 顶层 router：未配对 → 配对引导；已配对 → 主屏 |
| `Onboarding/` | 配对流程（流程 A） |
| `Home/HomeScreen.swift` | 主屏（流程 B） |
| `Home/StatusBadge.swift` | 绿/黄/红 connection badge |
| `Conversation/` | 对话进行中（流程 C） |
| `Privacy/CameraIndicator.swift` | 摄像头激活提示（流程 E） |
| `Settings/` | 暂停麦克风、解除配对、provider 选择 |

**Theming：** 与 UCLAW 桌面端保持视觉语言一致；使用 system 主题适配 light/dark + iOS 26+ Liquid Glass（如可用）。

**当前 UI 状态：** `ContentView` 仍直接路由到 `DevToolsRootView`。DevTools 是五个 tabs：Scan、Inspect、Send、Sense、Logs。它已经不再暴露任意 raw GATT 写入/订阅能力，而是优先通过 `LooiSession` 与 Motion/Head/Light/Sensor controllers 操作。raw topology / arbitrary notify inspection 被显式 deferred。

---

## 5. 数据模型

### 5.1 本地持久化（GRDB / SQLite）

```sql
-- 配对设备
CREATE TABLE paired_uclaws (
    id              TEXT PRIMARY KEY,         -- UCLAW device id
    host            TEXT NOT NULL,            -- last known host (LAN or tailnet)
    port            INTEGER NOT NULL,
    tls_fingerprint BLOB NOT NULL,
    ed25519_pubkey  BLOB NOT NULL,            -- UCLAW 公钥
    paired_at       INTEGER NOT NULL,
    last_seen       INTEGER NOT NULL,
    name            TEXT
);

CREATE TABLE paired_loois (
    id              TEXT PRIMARY KEY,
    ble_peripheral  TEXT NOT NULL,            -- CoreBluetooth identifier
    name            TEXT,
    firmware        TEXT,
    paired_at       INTEGER NOT NULL,
    last_seen       INTEGER NOT NULL
);

-- 离线 envelope queue
CREATE TABLE offline_envelopes (
    id              TEXT PRIMARY KEY,         -- ULID
    kind            TEXT NOT NULL,
    payload         BLOB NOT NULL,            -- CBOR bytes
    enqueued_at     INTEGER NOT NULL,
    attempts        INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX idx_offline_envelopes_enqueued ON offline_envelopes(enqueued_at);

-- 用户偏好
CREATE TABLE settings (
    key             TEXT PRIMARY KEY,
    value           TEXT NOT NULL
);
```

**Keychain（不放 SQLite）：** ed25519 私钥、UCLAW token、用户在 settings 启用的第三方 API key（ElevenLabs 等）。

### 5.2 内存状态

详见 §4.5 `AppState`。状态变更走 `@Observable`，UI 自动 reactive。

### 5.3 不持有的状态

- agent_messages / agent_sessions / memory_graph 全部留在 UCLAW；ulooi 只缓存最近 N 条用于"最近对话"摘要展示
- LLM provider keys 留在 UCLAW；ulooi 永不持有

---

## 6. 协议层 & Schema-first Codegen

### Wire envelope CDDL

`Schemas/wire-envelope-v1.cddl`（目标态：与 UCLAW repo 同源；通过 git submodule 或 release artifact 同步）：

```cddl
envelope = {
    v: uint,
    id: text,                       ; ULID
    ts: uint,                       ; ms wall clock
    src: text,                      ; device id
    kind: text,                     ; namespaced event type
    ? reply_to: text,
    payload: any,                   ; kind-specific
}

;; Selected payload schemas
voice_partial = { text: text, confidence: float }
voice_final = { text: text, speaker_id: ? text }
agent_token = { delta: text }
embodiment_touch = { location: text, intensity: float }
;; ...
```

### 代码生成 pipeline

```
Schemas/wire-envelope-v1.cddl
        │
        ├──► [build script] ──► Sources/Transport/Generated/Envelope+Generated.swift
        │
        └──► [build script] ──► uclaw repo / src-tauri/src/remote_bridge/wire.rs (Rust)
```

Swift 端：build phase script 在每次 build 前跑 codegen。Rust 端：M2 在 uclaw repo 集成时跑。**Schema 是单一真理源，两端类型派生。** 任何 envelope 字段改动 → CDDL 改 → 两边重新生成。

**当前状态：** 本仓库尚未落地 `Schemas/` 与 `Scripts/codegen-envelope.sh`。该段是 M2 contract 设计，不是当前代码事实。

### 不在 codegen 范围

- 业务 handler 逻辑
- 命名空间约定（仅做 docs 约束）
- TLS / pairing 协议（在 Pairing 子模块手写）

---

## 7. 依赖图（Module → Module）

```
UI
 └─► AppState
      └─► REFLEX/SENSORY (Modules/Reflex, Modules/Sensory)
            ├─► LooiKit (Packages/LooiKit)
            ├─► TRANSPORT (Modules/Transport)
            └─► Persistence (Storage/)

LooiKit  →  CoreBluetooth
TRANSPORT →  URLSession / Network.framework / CryptoKit
SENSORY  →  AVFoundation / Speech.framework
REFLEX  →  Apple Foundation Models / GRDB
```

无环。LooiKit 和 Transport 之间没有耦合。

---

## 8. 文件结构

```
ulooi/                              # repo root
├── README.md
├── .gitignore
├── ulooi.xcodeproj/
├── docs/
│   ├── prd.md
│   └── architecture.md             # 本文档
├── Packages/
│   └── LooiKit/                    # Swift Package
│       ├── Package.swift
│       ├── Sources/
│       │   ├── LooiKit/
│       │   └── LooiKitTesting/
│       └── Tests/
└── ulooi/                          # iOS app target
    ├── ulooiApp.swift              # @main entry
    ├── App/
    │   └── LooiBootstrap.swift     # 当前 app singleton
    ├── DevTools/                   # 当前 root UI
    │   ├── DevToolsRootView.swift
    │   └── Probe/
    ├── Shared/
    │   ├── BuildInfo.swift
    │   └── DevLog.swift
    ├── Resources/
    │   └── Assets.xcassets/
    ├── Info.plist
    └── ulooi.entitlements
```

---

## 9. 构建与部署

### Dev loop

- 主开发：Xcode 16+ workspace
- 命令行：`xcodebuild build -project ulooi.xcodeproj -scheme ulooi -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'`
- LooiKit 单独迭代：`cd Packages/LooiKit && swift test`
- Schema codegen：M2 尚未落地；目标态为 Xcode build phase 自动跑，也可手动 `./Scripts/codegen-envelope.sh`

### CI（M1 之后引入）

- GitHub Actions
- 矩阵：Swift 5.10 / 5.11、iOS 18.2 simulator
- 必跑：`xcodebuild test` + `swift test` (LooiKit) + schema codegen drift check
- 不跑：device tests（需要真机 + Looi 硬件，M0.5 prototype findings 决定是否上 self-hosted runner）

### TestFlight / 发布

- v1 (M5 ready) → TestFlight 内部（Ryan 家人）
- 公开发布在 P1 之后讨论

---

## 10. 测试策略

| 层 | 策略 | 工具 |
|---|---|---|
| LooiKit | unit tests via `MockBLETransport`; future protocol-level replay（`.bleskel` 文件） | XCTest + Swift Testing |
| Transport | envelope codec round-trip + WebSocket mock | XCTest |
| REFLEX | 状态机 transitions + offline queue replay | XCTest |
| SENSORY | mock AVAudioSession；ASR 用预录 .wav fixture | XCTest |
| UI | view snapshot test（关键 view） | Swift Testing + custom snapshot lib |
| 集成 | M3 之后引入：跑真 simulator + mock UCLAW transport | XCTest UI tests |
| E2E | 真硬件 + 真 UCLAW；手工 + 录屏 verification | manual + Charles for protocol log |

**Coverage 目标：** Modules/Reflex 和 LooiKit >= 80%；UI >= 30%（关键路径）。

---

## 11. 第三方依赖（SPM）

锁定列表（M1 时通过 Package.swift 引入）：

| 包 | 用途 | 备选 |
|---|---|---|
| [GRDB](https://github.com/groue/GRDB.swift) | SQLite WAL | SQLite.swift（不选，API 老） |
| [SwiftCBOR](https://github.com/valpackett/SwiftCBOR) 或 [PotentCodables](https://github.com/outfoxx/PotentCodables) | CBOR 编解码 | M1 时 prototype 后定，看哪个更适配 codegen |
| [swift-log](https://github.com/apple/swift-log) | 日志门面 | OSLog 直接（系统的，但 API 不灵活） |

不引入：Combine 库、DI 框架、第三方 BLE wrapper、第三方 UI 组件库。

---

## 12. 与 UCLAW 后端的契约边界

ulooi 不直接读写 UCLAW 任何 SQLite 表；目标态所有交互都通过 Wire envelope。UCLAW 后端改动汇总见 M0 spec §6 / M2 implementation plan。

对应 UCLAW workspace/repo family 是 `/Users/ryanliu/Documents/uclaw`；不要把本项目与旧记忆里的其它 UClaw/UCLAW 路径混用。ulooi 和 UCLAW 是独立 git repo，跨端变更必须分别提交和验证。

**契约保证：**

1. UCLAW 不假设 ulooi 任何特定实现 —— 只通过 envelope kind 看到事件
2. ulooi 不假设 UCLAW 内部 schema —— V27/V28/V29 是 UCLAW 自己的演化
3. Schema CDDL 是两端共同遵守的法律 —— 改动需双边同步

---

## 13. 演化路径（v1 后）

| 主题 | v1 状态 | 演化 |
|---|---|---|
| LooiKit | in-tree at `Packages/LooiKit/` | 可独立成 GitHub repo + Swift Package Index 发布 |
| Schemas | M2 尚未落地；目标是 repo-local + UCLAW 同源 | 可独立成 schemas-only repo，两端 submodule |
| iPad 适配 | 未做 | M1 spec 决定是否 v1 内做 |
| Apple Watch | 未做 | v2+，作为 "controller for Looi" 而非主入口 |
| 多 Looi 拓扑 | 不支持 | v2+ |
| 云中继（非 Tailscale 远程） | 不做 | 用户呼声大才考虑 |

---

## 14. 变更日志

| 日期 | 版本 | 变更 |
|---|---|---|
| 2026-05-17 | v0.1 | 初版；锁定 Pure SwiftUI/Swift 技术栈；模块分层；CDDL codegen 协议同步 |
