# ulooi M1.2 — Presence Slice: 它醒了

**Status:** Approved direction 2026-05-18  
**Program:** ulooi — iOS embodiment of UCLAW Agent through Looi robot  
**Predecessor:** `2026-05-17-ulooi-m1-foundation-design.md`  
**Scope:** Product/design spec only. Implementation plan follows after review.  
**Repo boundary:** this spec belongs to `/Users/ryanliu/Documents/uclaw/ulooi`; the paired UCLAW repo is `/Users/ryanliu/Documents/uclaw`. They are separate git repositories and must be managed separately.

---

## 1. Product Thesis

M1.2 should not merely add more remote-control buttons. It should make the first real product loop feel alive:

> A family member touches Looi, the robot body and the iPhone face respond together, and the user instinctively feels: it woke up.

ulooi is a dual-mode product:

1. **Looi Face Mode** — when the phone is connected to the Looi robot base over BLE, the app becomes Looi's expressive face in landscape.
2. **Standalone App Mode** — when the user carries the phone away without the robot base connected, ulooi behaves like a normal portrait iPhone app and preserves the same identity in a calmer app shell.

The product personality is:

> A small future family member: cute and companionable, clever and nimble, gently humorous, emotionally warm, and never annoying.

This means ulooi should feel closer to "a family member with a small body" than to "a BLE control panel" or "a generic chatbot."

## 2. Direction Decision: A + B

Ryan selected a combined direction:

- **A: Presence Core** — make Looi feel alive through idle presence, touch response, sleep/wake, cliff/suspended safety expression, and a few high-quality gestures.
- **B: Face-first** — make the iPhone screen carry Looi's expressive identity, especially in landscape face mode.

The combined decision is:

> M1.2 ships a minimum alive loop where face, light, head, and motion are choreographed by one Presence layer.

This rejects two tempting but weaker paths:

- Shipping only a beautiful face without body causality.
- Starting UCLAW transport first and delaying the embodied product feel.

M1.2 can prepare names and boundaries for future UCLAW integration, but it does not implement WebSocket, CBOR, UCLAW pairing, ASR, TTS, or long-term memory sync.

## 3. Current Code Truth

As of 2026-05-18:

- `Packages/LooiKit` already exists as a Swift Package.
- `LooiSession` owns the BLE lifecycle, FEDA handshake, reconnect policy, and controller access.
- Controllers exist for Motion, Head, Light, and Sensor.
- The app root still enters `DevToolsRootView`.
- Production Onboarding, Face Mode, Standalone App Mode, `GestureLibrary`, and Presence orchestration are not implemented yet.
- Sensor semantics still need replay verification before safety UX depends on nuanced FED9 interpretations.

M1.2 should build on the existing `LooiSession`/controller foundation while keeping DevTools available as a developer surface.

## 4. User Experience

### 4.1 First Launch and Pairing

Fresh install shows a short onboarding path:

1. Welcome to ulooi as a future family member, not a device utility.
2. Pair with nearby Looi.
3. After BLE ready, present Looi Face Mode when the phone is in landscape, or gently invite the user to rotate.

The onboarding copy should be warm and minimal. It should avoid UCLAW, CBOR, MCP, BLE jargon, and any heavy agent-system explanation.

### 4.2 Looi Face Mode (Landscape + BLE Connected)

When `LooiSession.state == .ready` and the UI is in landscape, the first screen is Looi's face:

- Full-screen black/near-black face stage.
- Large geometric eyes in M1.2; the renderer boundary stays open for future sprite assets.
- Soft mood glow, not decorative gradients.
- Minimal controls kept away from the face.
- Three primary actions: `wave`, `lookAtMe`, `sleep`.
- Small status indicators for connected, battery, and safety state.
- Settings entry that can reveal Developer tools.

The face is not a sticker. It must react in coordination with Looi's body:

- Touch event: face blink/surprise, light pulse, head micro-tilt.
- Idle: breathing glow, occasional gaze drift, small head settle.
- Wave: face brightens, head/light/motion sequence performs a greeting.
- Look at me: gaze centers, head centers or subtly lifts.
- Sleep: face closes, light dims, motion stops, head returns to safe center.
- Suspended/cliff: movement locks, face shows cautious concern, hint says the body needs support.

### 4.3 Standalone App Mode (Portrait or BLE Not Connected)

When the phone is not connected to the Looi base, ulooi should not look broken. It becomes a normal portrait app:

- Shows Looi's identity and current availability.
- Offers reconnect/pairing.
- Shows recent connection status and battery when known.
- Holds space for future UCLAW chat/memory without pretending M2 exists.
- Keeps the same personality, but with quieter motion and fewer face theatrics.

Standalone mode copy should feel like:

- "Looi is not nearby."
- "I'll reconnect when the little body is close again."
- "Last seen: just now" / "Battery last known: 87%" when available.

This mode makes the phone-carrying experience coherent: ulooi remains the companion app even when the robot base stays at home.

## 5. Personality Rules

ulooi's personality should be enforced as product rules, not only copywriting taste.

| Trait | Product meaning | Anti-pattern |
|---|---|---|
| Cute companion | Warm eye shapes, gentle timing, touch response | Babyish cartoon, noisy mascot behavior |
| Clever and nimble | Fast, context-aware micro reactions | Random animation unrelated to state |
| Future feeling | Clean geometry, luminous material, restrained UI chrome | Cold sci-fi dashboard, dense telemetry |
| Humorous | Short situational lines | Long jokes, meme text, sarcasm |
| Family member | Calm defaults, privacy-aware, non-intrusive | Always demanding attention |

Example microcopy tone:

- "我在。电量也还体面。"
- "脚下突然很哲学。先别让我开车。"
- "小身体已就位。"
- "我先眯一下，有事轻轻叫我。"

Microcopy must never explain implementation details such as BLE, characteristic IDs, packet decode, or UCLAW backend state.

## 6. Proposed Architecture

M1.2 introduces a small app-layer Presence system above LooiKit.

```
ulooi app
  Onboarding
  Main
    ModeController
    EmbodiedHomeView
    StandaloneHomeView
    PresenceDirector
    PresenceState
    FaceRenderer
    GestureLibrary
  Settings
    Developer -> existing DevTools

Packages/LooiKit
  LooiSession
  MotionController
  HeadController
  LightController
  SensorController
```

### 6.1 ModeController

Purpose: decide which top-level product surface is active.

Inputs:

- `LooiSession.state`
- orientation / size class
- onboarding completion
- last known paired Looi

Outputs:

- `.onboarding`
- `.faceMode`
- `.standalone`
- `.developer`

Initial rule:

- Connected + landscape -> `faceMode`
- Not connected or portrait -> `standalone`
- First launch without pairing -> `onboarding`
- Developer entry -> `developer`

M1.2 should not force an orientation. It should make landscape the best face experience while allowing portrait to be the normal app shape.

### 6.2 PresenceState

Purpose: normalize session and sensor signals into product states that UI and choreography can consume.

Proposed states:

- `.booting`
- `.lookingForBody`
- `.awake`
- `.idle`
- `.touched`
- `.performingGesture(GestureKind)`
- `.suspended`
- `.sleeping`
- `.disconnected`
- `.errorRecoverable`

`PresenceState` is app-layer state. It should not leak BLE packet details into views.

### 6.3 PresenceDirector

Purpose: choreograph face, light, head, and motion from a single source of intention.

Responsibilities:

- Map `PresenceState` to face expression, gaze, glow, and copy.
- Trigger safe light/head/motion sequences.
- Cancel/cleanup gestures when session leaves ready.
- Prevent overlapping gestures.
- Degrade gracefully when a controller command fails.

`PresenceDirector` should be conservative: all physical motion must remain gated by `MotionController` safety logic.

### 6.4 FaceRenderer

M1.2 should combine A+B by making Face part of the minimum loop.

Required v1 capabilities:

- idle eyes
- blink
- smile/soft happy
- surprised touch reaction
- sleepy
- cautious/suspended
- disconnected/looking
- gaze center/left/right/up/down

M1.2 defaults to a geometric SwiftUI Canvas implementation. The boundary should allow a future sprite or generated face renderer, but the implementation plan should not depend on sprite assets.

### 6.5 GestureLibrary v0

Only three gestures are needed for M1.2:

1. `wave`
2. `lookAtMe`
3. `sleep`

Each gesture should coordinate:

- face expression
- head position
- light brightness/pulse
- optional safe motion
- cleanup back to idle or sleeping

Do not ship six mediocre gestures. Three polished rituals are better for the "family member" feeling.

## 7. Dual-mode Behavior Matrix

| Condition | Surface | Orientation | Physical Looi | User feeling |
|---|---|---|---|---|
| First launch, no pairing | Onboarding | Portrait-first | None | "I can set up a little companion." |
| BLE connected + landscape | Face Mode | Landscape | Active | "The phone is Looi's face." |
| BLE connected + portrait | Standalone App Mode | Portrait | Available | "I can manage Looi like a normal app." |
| BLE disconnected + portrait | Standalone App Mode | Portrait | Away | "Looi is not here, but the app is still useful." |
| BLE disconnected + landscape | Standalone App Mode with looking-for-body state | Landscape | Away | "Looi is waiting for the little body." |
| Cliff/suspended | Face Mode safety state | Landscape | Motion locked | "It knows its body is unsafe." |

## 8. Error and Safety Design

M1.2 should use safety as personality, not as engineering noise.

- BLE unavailable: explain that Looi cannot connect right now; offer retry.
- Not connected: keep standalone mode usable.
- Cliff/suspended: lock driving/motion, show cautious face, keep head/light allowed if safe.
- Gesture interrupted: cleanup motor, light, and head best-effort.
- Battery low: reduce animation frequency and suggest rest.

Important safety boundary:

> `MotionController` remains the hard physical motion gate. UI state can explain and predict, but must not be the only safety layer.

Because sensor semantics still require replay validation, M1.2 implementation should include sensor truth tests before relying on nuanced FED9 state for user-facing safety messages.

## 9. Testing and Validation

M1.2 should be verified at four levels:

1. **Unit tests**
   - `ModeController` surface selection.
   - `PresenceState` derivation.
   - `PresenceDirector` command sequencing with mock LooiKit.
   - Gesture cancellation/cleanup.

2. **Snapshot or visual tests**
   - Face expressions for idle, touched, sleeping, suspended, disconnected.
   - Portrait standalone app layout.
   - Landscape face mode layout.

3. **Simulator smoke**
   - First launch -> onboarding.
   - Mock connected -> landscape face mode.
   - Portrait -> standalone app mode.
   - Settings -> Developer -> existing DevTools.

4. **Real Looi smoke**
   - Connect -> face mode ready.
   - Touch -> face/light/head response.
   - Wave -> physical gesture completes.
   - Sleep -> light/head/motion settle.
   - Lift/suspend -> movement locks and safety personality appears.
   - Walk away/disconnect -> standalone remains coherent.

## 10. Definition of Done

M1.2 is done when:

1. The app no longer boots ordinary users directly into DevTools.
2. Connected + landscape shows Looi Face Mode.
3. Portrait or disconnected shows Standalone App Mode.
4. Face, light, head, and motion respond together to at least touch, wave, look-at-me, and sleep.
5. Suspended/cliff state is represented as a bodily boundary, not a generic error.
6. Existing DevTools remain reachable from a developer path.
7. LooiKit tests still pass.
8. A real family member can touch Looi once and understand, without explanation, that it responded.

## 11. Non-goals

- No UCLAW WebSocket/CBOR transport.
- No UCLAW pairing flow.
- No ASR/TTS.
- No long-term memory writeback.
- No background BLE mode.
- No complex autonomous wandering.
- No six-gesture library.
- No telemetry-heavy dashboard as the primary surface.

## 12. Implementation Defaults

The implementation plan should use these defaults unless Ryan explicitly changes direction:

1. Start with a geometric SwiftUI Canvas FaceRenderer.
2. Keep Developer visible during TestFlight/internal builds.
3. Do not force orientation; select mode from current orientation/size.
4. Add sensor replay tests before making suspended/cliff copy more specific than "the body needs support."
