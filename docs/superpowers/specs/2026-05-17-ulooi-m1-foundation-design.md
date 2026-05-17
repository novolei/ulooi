# ulooi M1 — Foundation: LooiKit Package + Dual-mode shell + Face Engine v1 + Gestures

**Status:** Approved 2026-05-17
**Program:** ulooi (novolei/ulooi) — iOS embodiment of UCLAW Agent
**Predecessor:** M0 umbrella spec — currently in uclaw repo at `uclaw/docs/superpowers/specs/2026-05-17-ulooi-design.md` (will be mirrored into this repo's `docs/superpowers/specs/` next time M0 is updated)
**M0.5 reference:** [`docs/m0-5-prototype-findings.md`](../../m0-5-prototype-findings.md) (BLE protocol, cliff lockout, FED9 decode)
**Duration:** 3-4 weeks · **PRs:** 3 (bisectable) · **Owner:** Ryan, opus + sonnet + haiku collaboration

---

## 1. Vision (North Star)

A family member picks up the iPhone in landscape, the app auto-reconnects to a previously-paired Looi, and the screen becomes Looi's face — large expressive eyes, mood-driven background gradient ("Dreams Wallpaper"), and six satellite gesture buttons in a ring (Wave / Look at me / Dance / Drive / Patrol / Settings). Tap a button → Looi performs the gesture (wave hands by blinking the headlight + tilting head up, dance by spinning + light sync, etc.). No emoji, no chrome — **iPhone IS Looi's face**.

If Looi is not nearby (BLE not connected), or the user rotates to portrait, the app shows a Standalone Mode placeholder: "Looi not nearby — UCLAW chat coming in M2" with Settings + Try Reconnect buttons. Both modes are presences of the same UCLAW Agent identity; M2 wires the chat surface to the Rust backend.

## 2. Goals (4 parallel)

1. **LooiKit Swift Package extraction** — lift `ulooi/LooiKit/*` to `Packages/LooiKit/`, define `BLETransport` protocol, inject `CoreBluetoothTransport` (prod) / `MockBLETransport` (test). Public API: `LooiSession`, 4 Controllers (Motion / Head / Light / Sensor), `GestureLibrary`, `FaceRenderer` types. Internal: BLE implementation details.
2. **Production UI replaces DevTools as the primary surface** — `ulooi/{Onboarding, Main, Settings}/` new top-level structure. Embodied (landscape) is the Dreams Wallpaper face. Standalone (portrait) is the M2 placeholder. DevTools migrates under Settings → Developer.
3. **Face Engine v1 (Geometric)** — `FaceRenderer` protocol + `GeometricFaceRenderer` implementation (SwiftUI Canvas). 9 expressions × 5 fixed gaze directions (+ `follow(CGPoint)` for future pointer/finger tracking) × Mood tint. `DefaultMoodMapper` derives expression/mood from `LooiSession` state (M3 swaps mapper for Agent-driven mood).
4. **GestureLibrary v1** — `actor` with 6 imperative-async preset gestures: `wave()`, `lookAtMe()`, `dance()`, `patrol()`, `sleep()`, `celebrate()`. M3 Agent calls these directly via `await session.gestures.wave()`.

## 3. Out of Scope (explicit)

- ❌ **Nano Banana asset generation** — moved to new M1.5 milestone (2-3 weeks, separate PR)
- ❌ **Dynamic dream scene generation** — M1 uses 3-5 static presets; M3 Agent drives true generation
- ❌ **Touch zone differentiation** (FED9 type 0x09 side detection) — captured opportunistically during M1 development, spec'd as deferred
- ❌ **Full 4-direction cliff sensor mapping** — front cliff (b1) is confirmed in M0.5; full mapping deferred to M2 if needed
- ❌ **UCLAW connection** (Rust backend / iOS network layer / pairing / CBOR) — M2
- ❌ **iPad layout optimization** — iPhone landscape primary; iPad landscape inherits but is not tuned
- ❌ **iOS background BLE** — foreground-only assumption; M5 reflex layer handles background
- ❌ **No changes to uclaw repo** — ulooi is fully independent; M2 will add UCLAW transport

## 4. Definition of Done (M1 ship gate)

1. Family member installs via TestFlight → first launch → onboarding → pair Looi → sees Looi face + large eyes on main screen
2. Tap Wave → Looi physically waves (gesture sequence completes)
3. Open Drive sheet → joystick controls Looi; cliff sensor lock → joystick greys out with "Put me down to drive" hint
4. Disconnect / restart app → auto-reconnect → returns to Looi face within seconds without re-pairing
5. Settings → Developer → opens five DevTools tabs (M0.5 probes preserved as debug tools)
6. LooiKit Swift Package has standalone unit tests (mock BLE, validates SessionState machine + Controller command encoding)
7. Cliff sensor lock → `MotionController.setMotion` is no-op + throws `cliffLocked` + UI shows suspended state
8. Real-hardware smoke checklist (`docs/m1-smoke-test-checklist.md`) all 8 steps pass

---

## 5. Architecture

### 5.1 Three-layer dependency

```
┌─────────────────────────────────────────────────────────────┐
│  ulooi app (ulooi/)                                          │
│  Onboarding / Main / Settings / DefaultMoodMapper / DevTools │
└────────────────────────┬────────────────────────────────────┘
                         │ depends on
┌────────────────────────▼────────────────────────────────────┐
│  LooiKit Package (Packages/LooiKit/)                         │
│  LooiSession / Controllers / GestureLibrary / FaceRenderer   │
│  BLETransport protocol                                       │
└────────────────────────┬────────────────────────────────────┘
                         │ injects
┌────────────────────────▼────────────────────────────────────┐
│  CoreBluetoothTransport (prod)  |  MockBLETransport (test)   │
└─────────────────────────────────────────────────────────────┘
```

LooiKit knows nothing about app shell, UI, or mood mapping. App layer composes LooiKit primitives into Views. BLE concerns live behind `BLETransport` — testable end-to-end without hardware.

### 5.2 LooiSession state machine (9 states)

```
.disconnected ──user.connect()──▶ .scanning
.scanning ──peripheral.discovered──▶ .connecting
.connecting ──gatt.connected──▶ .discovering
.discovering ──chars.found──▶ .handshaking
.handshaking ──FEDA.ok──▶ .ready
.ready ──BLE.disconnected──▶ .reconnecting
.reconnecting ──(within 60s)──▶ .scanning
.reconnecting ──(timeout 60s)──▶ .disconnected
```

Backoff during `.reconnecting`: 1s → 2s → 4s → 8s → 16s → 30s → 30s (capped). Total reconnect window: 60s. Scan name filter: `advertisement.localName.contains("LOOI")`. Last paired `peripheral.identifier` persisted in `UserDefaults`; attempted first on reconnect.

### 5.3 Controllers (public API)

- **`MotionController`** — `setMotion(_:)`, `forward/back/left/right(speed:)`, `spin(_:speed:)`, `stop()`. Owns the 30ms motor heartbeat to FED0 with `.withoutResponse`. Hard-blocks on `cliffState != .grounded`.
- **`HeadController`** — `lookUp()`, `lookDown()`, `center()`. Writes FED1 (pitch). From M0.5 hardware testing: `0x00` = head up, `0x5A` = center (used by `center()`), `0xFF` = head down momentarily then auto-spring back to center (used by `lookDown()`). Caller must not assume `lookDown()` holds — for "stay down" behavior, repeat writes (out of scope for M1 gestures).
- **`LightController`** — `set(brightness:)` (0...1 analog), `off()`. Writes FED2.
- **`SensorController`** — exposes `cliffState`, `imu`, `batteryPercent`, `touchEvent` as `@Observable` properties. Owns the 4s FED8 battery poll. Decodes FED9 multi-packet (type 0x01 cliff / 0x02 IMU / 0x09 touch / 0x11 boot).

### 5.4 Invariants (I1-I8)

| # | Invariant |
|---|---|
| I1 | `LooiSession.state` mutated single-threaded (@MainActor); observers see consistent snapshots |
| I2 | `.ready` ⇔ motor heartbeat (30ms .withoutResponse to FED0) is running |
| I3 | `.ready` ⇔ battery poll (4s FED8 read) is running |
| I4 | Enter `.disconnected` / `.reconnecting` → heartbeat + battery poll stop immediately |
| I5 | All state transitions go through single `setState()` (single log point + single observer notify) |
| I6 | `motion.stop()` called once on each: `.ready → .reconnecting/.disconnected`; cliff state grounded→suspended; `willResignActive` / `didEnterBackground` |
| I7 | Gesture cancel runs cleanup (motor stop + light off + head center, all best-effort, throws swallowed) |
| I8 | ≤ 1 in-flight Gesture task (`GestureLibrary` actor guarantees) |

### 5.5 Errors (`LooiError`)

```swift
public enum LooiError: Error, LocalizedError {
    case bluetoothUnauthorized
    case bluetoothPoweredOff
    case peripheralNotFound(timeout: TimeInterval)
    case connectionFailed(underlying: Error)
    case handshakeFailed(step: HandshakeStep)
    case characteristicMissing(CBUUID)
    case writeFailed(CBUUID, underlying: Error)
    case cliffLocked(directions: CliffState)
    case sessionNotReady(state: SessionState)
    case gestureCancelled
}
```

Localized descriptions ship Chinese primary + English fallback.

---

## 6. UI Detailed Design

### 6.1 Embodied Mode (landscape)

```
┌──────────────────────────────────────────────────────────┐
│  [● Connected · 87%]                            [⚙]      │
│                                                          │
│      [👋 Wave]               [🚀 Drive]                  │
│                                                          │
│              ╭─────────────────────╮                     │
│              │                     │                     │
│              │     ◉      ◉        │     ← Face         │
│              │                     │       (animated)    │
│              │   curious · listen  │                     │
│              ╰─────────────────────╯                     │
│                                                          │
│      [👀 Look]               [🛡  Patrol]                │
│                                                          │
│         [💃 Dance]      [😴 Sleep]                       │
└──────────────────────────────────────────────────────────┘
```

`ZStack`: `DreamsWallpaperView(tint: mood.tint)` → `GeometricFaceRenderer(...)` → `GestureRingOverlay(buttons:6)`. The six ring buttons are **Wave / Look at me / Dance / Drive / Patrol / Settings**:
- Wave / Look at me / Dance / Patrol — trigger `GestureLibrary` actions
- Drive — opens a modal sheet with a virtual joystick (continuous motion control, not a gesture)
- Settings — navigates to SettingsRootView

The remaining two `GestureLibrary` actions (`sleep()`, `celebrate()`) are **not** in the ring — `sleep()` is auto-triggered by low-battery logic (Section 9.2); `celebrate()` is reserved for M3 Agent-driven moments (e.g. "task completed"). M1 still exposes both via `LooiSession.gestures` so DevTools can fire them for testing.

### 6.2 Standalone Mode (portrait)

Placeholder card centered: "🤖 Looi not nearby — UCLAW chat coming in M2", with `[⚙ Settings]` and `[🔄 Try Reconnect]` buttons. Persistent across portrait usage.

### 6.3 Onboarding (portrait, 3 steps)

1. **Welcome** — "Meet Looi" + hero image + Continue
2. **Scanning** — animated radar + "Make sure Looi is on and nearby"
3. **Ready** — checkmark + "Rotate to landscape to see Looi" + Done

### 6.4 Mode switching

`ModeController` observes `LooiSession.state` + `UIDevice.orientation`. Transitions use 500ms fade. Connecting to Looi while in portrait → toast prompt "Rotate to landscape to see Looi"; we do not force-rotate.

`Info.plist`:
- `UISupportedInterfaceOrientations` = landscape (left + right) + portrait

Per-view orientation lock (Embodied = landscape only, Onboarding/Standalone = portrait only) is implementation-deferred to PR 3: choose between (a) iOS 16+ `requestGeometryUpdate(.iOS(interfaceOrientations:))` on the active windowScene, or (b) overriding `UIApplicationDelegate.application(_:supportedInterfaceOrientationsFor:)` with an `@Observable` orientation gate. Decision recorded in PR 3 commit.

---

## 7. Face Engine v1

### 7.1 FaceRenderer protocol

```swift
public protocol FaceRenderer: View {
    var expression: FaceExpression { get }
    var gaze: GazeDirection { get }
    var mood: Mood { get }
    var breathPhase: Double { get }  // 0...1, driven by BreathClock
}

public enum FaceExpression: Sendable {
    case idle, curious, happy, surprised,
         sleepy, alert, blink, sad, focused
}

public enum GazeDirection: Sendable {
    case center, left, right, up, down, follow(CGPoint)
}

public struct Mood: Sendable {
    public let energy: Double   // 0...1 (sleepy → wired)
    public let valence: Double  // -1...1 (sad → happy)
    public let tint: Color      // derived (drives background gradient)
}
```

Renderer is stateless — state injected. Enables `GeneratedFaceRenderer` (M1.5 Nano Banana sprites) to be a drop-in replacement.

### 7.2 GeometricFaceRenderer (M1)

SwiftUI `Canvas` single-pass draw: background gradient → eye shapes (per expression) → highlight dots (per gaze) → optional brows (sad/surprised) → breath scale modifier ±2%. 60fps target. No image assets, no SF Symbols, no emoji.

**Expression → shape map:**

| Expression | Eye shape | Extra |
|---|---|---|
| .idle | round ellipse | breath only |
| .curious | round ellipse | tilted 5° |
| .happy | upward crescent | (smile eyes) |
| .surprised | large circle | brows raised |
| .sleepy | flat ellipse | (half-closed) |
| .alert | sharp narrow ellipse | (squinting) |
| .blink | horizontal line | 50ms |
| .sad | downward crescent | brows ∧ |
| .focused | small dot | (staring) |

**Animation timing:** blink every 4-7s random; breath 5s sin period ±2% scale; expression morph `.spring(response:0.35, dampingFraction:0.7)`; gaze shift 200ms ease-out; mood tint 1.5s ease-in-out.

### 7.3 DefaultMoodMapper (app layer)

Lives in app target, not LooiKit. M3 swaps for Agent-driven mapper.

| Session state | Expression | Mood (energy, valence) |
|---|---|---|
| .disconnected | .sleepy | (0.2, 0) |
| .scanning / .connecting | .curious | (0.6-0.7, 0.3) |
| .handshaking | .focused | (0.7, 0.2) |
| .ready (idle) | .idle | (0.5, 0.5) |
| .driving | .alert | (0.9, 0.6) |
| .gesture(.wave) | .happy | (0.8, 0.9) |
| .gesture(.dance) | .happy | (1.0, 1.0) |
| .cliffLocked | .surprised | (0.7, -0.3) |
| .lowBattery | .sleepy | (0.1, -0.2) |
| .tap (FED9 0x09) | .surprised → .idle after 600ms | — |
| .userTouch | .happy → .idle after 1.2s | — |

---

## 8. GestureLibrary v1

### 8.1 API

```swift
public actor GestureLibrary {
    public func wave() async throws
    public func lookAtMe() async throws
    public func dance() async throws
    public func patrol() async throws
    public func sleep() async throws
    public func celebrate() async throws
    public func cancel() async
}
```

Actor serializes execution: launching a new gesture cancels the current task. Imperative async functions (no DSL) — YAGNI.

### 8.2 Six gestures

| Gesture | Cliff-safe? | Duration | Effect |
|---|---|---|---|
| `wave()` | ✅ (head + light only) | ~2.5s | Head up → 3× light blink → head center |
| `lookAtMe()` | ✅ | ~1.2s | Head up → dim light on → stays |
| `dance()` | ❌ (needs grounded) | ~6s | 6 beats of alternating spin + light sync |
| `patrol()` | ❌ | loop | Forward 1.5s → stop → head left/right → repeat until cancel |
| `sleep()` | ✅ | ~3s | Stop motor → head down → light fade |
| `celebrate()` | ✅ | ~3s | Head up → 8× fast light blink → center |

Cliff-locked gestures throw `LooiError.cliffLocked(...)` at entry; UI shows "Put me down to dance 🙂".

### 8.3 Cancellation semantics

- New gesture → current task `cancel()` → cleanup runs (motor stop + light off + head center, best-effort)
- BLE disconnect → controller methods throw → gesture propagates → UI catches
- Cliff lock mid-gesture → `MotionController` no-ops + throws; head/light continue (dance degrades to "head + light only")

---

## 9. Safety + Reconnect + Lifecycle

### 9.1 Cliff strategy: hard-block in MotionController

`MotionController.setMotion(_:)` reads the latest `SensorController.cliffState` snapshot. If any wheel is suspended → no-op + throw `LooiError.cliffLocked(directions:)`. UI observes `cliffState` for visual hints (grey joystick, suspended pill) but does not enforce. **MotionController is the only safety gate** — M3 Agent will hit the same wall.

### 9.2 Battery behavior

| Battery | Behavior |
|---|---|
| > 30% | Normal |
| ≤ 30% | Orange pill "Low battery N%", `mood.energy *= 0.7`, dance/patrol show "Looi is tired" |
| ≤ 10% | Auto-trigger `sleep()`, disable dance/patrol, red pill "Critically low — please charge" |
| Missing 3× | Show "?", do not block features |

### 9.3 App lifecycle

| Event | Action |
|---|---|
| `willResignActive` | `motion.stop()` once; heartbeat continues |
| `didEnterBackground` | Cancel all gestures + `motion.stop()` + stop heartbeat/battery poll |
| `willEnterForeground` | If `.disconnected` → trigger `.scanning` (resume auto-reconnect) |
| Orientation change | Session unaffected; ModeController re-evaluates mode |

---

## 10. Testing Strategy

### 10.1 Three-layer pyramid

| Layer | Target | Tech | Scope |
|---|---|---|---|
| L1: LooiKit unit | `LooiKitTests` | XCTest + `MockBLETransport` | SessionState transitions, handshake, heartbeat invariants, command bytes, cliff hard-block, gesture cancel |
| L2: Face snapshot | `LooiKitTests` + `swift-snapshot-testing` | SwiftUI snapshot | 9 expr × 5 gaze = 45 + mood/breath/blink frames |
| L3: ulooi smoke | `ulooiUITests` | XCUITest, simulator | Launch → Onboarding; Embodied elements; Standalone placeholder; Settings → DevTools |

### 10.2 BLETransport protocol

```swift
public protocol BLETransport: Sendable {
    func scan(nameFilter: String) -> AsyncStream<DiscoveredPeripheral>
    func connect(_ peripheral: DiscoveredPeripheral) async throws -> ConnectedPeripheral
    func write(_ data: Data, to: CBUUID, type: WriteType) async throws
    func read(from: CBUUID) async throws -> Data
    func subscribe(to: CBUUID) -> AsyncStream<Data>
}
```

`MockBLETransport` exposes `writes: [(CBUUID, Data, WriteType)]` for assertions and `simulateNotification(on:data:)` / `simulateDisconnect()` for state injection.

### 10.3 Test case checklist (M1 must-pass)

`SessionStateMachineTests`, `HandshakeTests`, `HeartbeatInvariantTests`, `MotionControllerTests`, `GestureLibraryTests`, `FaceRendererSnapshotTests`, `ulooiUITests` — see Section 7 of brainstorm for full enumeration. ~20 named cases.

### 10.4 Real-hardware smoke checklist

8-step manual checklist in `docs/m1-smoke-test-checklist.md`, ran before each release. Single-person project — auto-hardware-CI cost > value, deferred.

### 10.5 CI

GitHub Actions on macOS runner. PR runs `xcodebuild test -scheme LooiKit -destination 'platform=iOS Simulator,name=iPhone 16'` covering L1 + L2 + L3. Snapshot first-failure uploads new images as artifact; PR description must note "visual change reviewed".

---

## 11. Milestone Sequence (3 PRs)

```
PR 1 ───────▶ PR 2 ───────▶ PR 3
(foundation)  (presence)    (production shell)

Week 1 ─ PR 1 (LooiKit Package extraction)
Week 2 ─ PR 2 part 1 (Face + Wallpaper)
Week 3 ─ PR 2 part 2 (Gestures + Embodied) ──▶ PR 2 ship
Week 4 ─ PR 3 (Dual-mode shell + Onboarding + Settings + ship)
```

Total: 3-4 weeks; Week 4 carries ~3 days slack.

### 11.1 PR 1 — LooiKit Package extraction (~1 week, 10 commits)

**Scope:** Scaffold `Packages/LooiKit/`, lift code, define `BLETransport`, rewrite `BLECentral` → `LooiSession` + injected transport, formalize state machine + invariants, ship 4 typed Controllers, `LooiError`, `MockBLETransport` in `LooiKitTesting`, L1 unit test suite.

**DoD:** App target no longer imports CoreBluetooth directly; DevTools five tabs preserve M0.5 behavior on real hardware; LooiKit unit tests pass; full real-Looi smoke (scan → connect → handshake → ready → drive → stop → disconnect → reconnect) passes.

**Branch:** `plan/m1-pr1-looikit-package`

### 11.2 PR 2 — Face Engine + Gestures + Embodied Mode (~1.5 weeks, 13 commits)

**Scope:** `FaceRenderer` protocol + `GeometricFaceRenderer`, `BreathClock`, `DreamsWallpaperView` (5 presets), `DefaultMoodMapper`, `GestureLibrary` actor + 6 gestures, cliff hard-block in MotionController, `EmbodiedMainView` + `GestureRingOverlay` + Drive sheet, L2 snapshot suite, L1 GestureLibrary tests.

**DoD:** Landscape launches into EmbodiedMainView (DevTools removed from root); all 6 ring buttons function correctly on real hardware (4 gesture buttons trigger their gestures, Drive opens working joystick sheet, Settings opens SettingsRootView); cliff lock UX (grey joystick + suspended pill); Face expression follows session state; snapshot tests pass.

**Branch:** `plan/m1-pr2-face-and-gestures`

### 11.3 PR 3 — Dual-mode shell + Onboarding + Settings + ship (~1 week, 13 commits)

**Scope:** `ModeController` (BLE + orientation), Info.plist landscape+portrait, `OrientationLock`, `StandalonePlaceholderView`, `OnboardingFlow` (3 steps), `SettingsRootView` + Developer section with DevTools, cliff suspended UX, low-battery UX, app lifecycle hooks, L3 XCUITest smoke, real-hardware smoke checklist run, version bump to 0.2.0.

**DoD:** Fresh install → onboarding → pair → Embodied; landscape↔portrait smooth; auto-reconnect + 60s timeout works; Settings → Developer reaches all five DevTools tabs; low-battery + cliff UX visible; app background/foreground transitions correct; 8-step real-hardware checklist passes; XCUITest CI green.

**Branch:** `plan/m1-pr3-dual-mode-shell`

### 11.4 Per-PR superpowers ritual

For each PR:
- Branch: `plan/m1-pr{N}-{slug}`
- Before opening PR: `/qa` + `/review` + real-hardware smoke
- PR description includes `## Commits (bisectable)` table
- After merge: `/retro` writes ulooi `learnings.jsonl`

---

## 12. Risks + Open Questions

| Risk | Mitigation |
|---|---|
| Face Canvas visual quality below "Looi brand" bar | PR 2 ships geometric as v1; M1.5 immediately follows with Nano Banana option; users can toggle in Settings (M1.5) |
| Snapshot tests flake across Xcode / simulator versions | Pin simulator name + Xcode version in CI; commit snapshot images per device class |
| Cliff sensor 4-direction mapping incomplete (only front confirmed in M0.5) | Front cliff = safe-enough baseline for M1 (any suspended state → all-stop); finer mapping deferred to M2 |
| Auto-reconnect 60s timeout too short / long | Configurable in M1 Settings → Developer; default 60s; collect telemetry in M2 |
| Standalone placeholder feels unfinished to family users | Placeholder text is intentional, sets expectation for M2; M1 release notes call out "two screens, one identity" |
| Embedded DevTools cause confusion when accidentally tapped | Settings → Developer requires 5 taps on version label to reveal (M1 hidden gate) |

**Open questions (resolved by build time, not blocking spec):**
- FED9 type 0x09 touch zone differentiation (left/right/top) — backfill during M1
- BreathClock global singleton vs per-renderer — likely singleton; confirm during PR 2

---

## 13. Out-of-band changes required

- **`m0-spec` (M0 umbrella)** needs update to reflect:
  - New M1.5 milestone (Nano Banana faces, 2-3 weeks)
  - M2 expansion: UCLAW transport + Standalone Mode real chat UI (was just transport)
  - M3+ unchanged
- **`docs/m1-smoke-test-checklist.md`** new file (created in PR 3)
- **`Packages/LooiKit/Package.swift`** new file (created in PR 1)
- **`ulooi/ulooi.xcodeproj/project.pbxproj`** edits in PR 1 (Local Package dependency)

No changes to uclaw repo (`src-tauri/`, `ui/`).

---

## 14. Appendix — Looi BLE protocol (from M0.5)

See [`docs/m0-5-prototype-findings.md`](../../m0-5-prototype-findings.md) for canonical reference. Summary for spec readers:

- **Service 6E40...FF00 / 00FF** — primary command service
- **FED0** — motion (4-byte: speed L, speed R, durMS L, durMS H, direction)
- **FED1** — head pitch (1-byte: 0x00 up, 0x5A center, 0xFF down-then-spring)
- **FED2** — light analog brightness (1-byte: 0x00 off ... 0xFF full)
- **FED5** — sensor notifications (subscribe)
- **FED8** — battery (read, 1-byte percent)
- **FED9** — telemetry multi-packet (type byte first):
  - `0x01` cliff (1-byte bitfield: b1=front suspended)
  - `0x02` IMU (6-byte int16 x,y,z)
  - `0x09` touch event
  - `0x11` boot status
- **FEDA** — handshake step ack
- **2A29** — manufacturer string (read to wake)

**Handshake sequence:** Read 2A29 → Write 0x01 → wait FEDA → Subscribe FED5+FED9 → Write 0x03 → wait FEDA → start motor heartbeat (30ms .withoutResponse to FED0) + battery poll (4s read FED8).
