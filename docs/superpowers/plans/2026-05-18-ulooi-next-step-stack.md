# ulooi Next-Step Stack Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement each slice. For product/architecture reviews, use gstack reviews as checkpoints: `/plan-ceo-review`, `/plan-eng-review`, `/plan-design-review`, `/review`, and `/qa`.

**Goal:** Move ulooi from M1 PR1 foundation into a trustworthy M1 product slice without crossing into UCLAW M2 too early.

**Architecture:** Keep `ulooi` focused on Looi embodiment foundation first: BLE truth, controller safety, DevTools fidelity, gestures, then production shell. UCLAW remains a separate git repo rooted at `/Users/ryanliu/Documents/uclaw`; `ulooi` is the nested independent repo at `/Users/ryanliu/Documents/uclaw/ulooi`.

**Tech Stack:** Swift 6, SwiftUI, Observation, CoreBluetooth, XCTest, LooiKit Swift Package, gstack review skills, Superpowers planning/execution skills.

---

## Executive Decision

Do **not** start M2 UCLAW transport yet. The next best move is to stabilize M1 on hardware truth and product shell:

1. Lock FED9 sensor semantics with replay fixtures.
2. Preserve and document real-hardware smoke flow.
3. Add GestureLibrary only after sensor safety is trustworthy.
4. Replace DevTools root with production shell while keeping DevTools under Settings.
5. Then open M2 UCLAW contract planning as a separate repo-pair stack.

This is a scope reduction in the CEO sense: fewer shiny surfaces, more trust. If cliff/touch/IMU semantics are wrong, every later gesture, drive sheet, and Agent-triggered action inherits a bad safety gate.

## gstack / Superpowers Workflow

Use gstack as review gates, not as a replacement for implementation plans.

| Stage | Skill / command | Purpose |
|---|---|---|
| Before executing this plan | `/plan-ceo-review` or `/autoplan` | Confirm scope: sensor truth before UI/transport |
| Before each code PR | `superpowers:writing-plans` | Create a concrete task-level plan |
| During execution | `superpowers:executing-plans` or subagent-driven development | Follow tasks and verification |
| After implementation | `/review` | Code review stance: bugs, regressions, missing tests |
| For production shell UI | `/plan-design-review` before coding, `/design-review` after screenshots | Avoid AI-looking UI and layout mistakes |
| Before merging a slice | `/qa` where simulator/UI applies, `swift test` always | End-to-end confidence |

Installed gstack note: user-level gstack exists at `~/.claude/skills/gstack`; do not run team mode in this repo unless explicitly requested, because that would add `.claude/` / `CLAUDE.md` and commit repo policy.

## Stack Overview

Treat these as stacked work slices. Each slice should be a separate branch and PR in the `ulooi` git repo.

| Order | Branch | Outcome | Blocks |
|---|---|---|---|
| 1 | `codex/m1-sensor-truth-replay` | FED9/FED8 semantics verified by replay tests and docs | Gesture safety, Drive UI |
| 2 | `codex/m1-hardware-smoke-checklist` | Repeatable real-Looi verification checklist and DevTools logging hooks | PR confidence |
| 3 | `codex/m1-gesture-library` | Safe async GestureLibrary over existing controllers | Production embodied mode |
| 4 | `codex/m1-production-shell` | Root UI becomes onboarding/embodied/standalone; DevTools moves under Settings | TestFlight-family flow |
| 5 | `codex/m2-uclaw-contract-plan` | Separate ulooi + UCLAW contract plan for CBOR/WebSocket/pairing | M2 implementation |

Do not mix `ulooi` and UCLAW commits. Slice 5 may create one plan in each repo, but implementation must remain two independent git histories.

---

## Slice 1: Sensor Truth Replay

**Goal:** Make `SensorController` match real M0.5 data instead of optimistic assumptions.

**Why first:** Current code decodes `FED9 type 0x01` as a one-byte bitfield and `type 0x02` as 3-axis little-endian 7-byte IMU. M0.5 findings describe a 5-byte cliff packet and 3-byte IMU-like samples with big-endian-looking values. This is the biggest correctness risk in the stack.

**Files:**

- Modify: `Packages/LooiKit/Sources/LooiKit/Controllers/SensorController.swift`
- Modify: `Packages/LooiKit/Sources/LooiKit/Models/CliffState.swift`
- Modify: `Packages/LooiKit/Tests/LooiKitTests/SensorControllerTests.swift`
- Create: `Packages/LooiKit/Tests/LooiKitTests/Fixtures/FED9Samples.swift`
- Modify: `docs/m0-5-prototype-findings.md`
- Modify: `docs/architecture.md`

**Tasks:**

- [ ] Capture M0.5 sample packets into a typed fixture file:
  - `bootComplete = Data([0x11, 0x01, 0x00])`
  - `groundedCandidate = Data([0x01, 0x01, 0x01, 0x01, 0x01])`
  - `frontLiftCandidate = Data([0x01, 0x00, 0x01, 0x01, 0x01])`
  - `touchDown = Data([0x09, 0x01])`
  - `touchUp = Data([0x09, 0x00])`
  - `imuCandidate = Data([0x02, 0xff, 0xf8])`
- [ ] Write failing tests that prove current decode ambiguity:
  - grounded candidate must not be treated as suspended without an explicit mapping decision.
  - front lift candidate must decode as front suspended if we adopt the M0.5 mapping.
  - 3-byte IMU candidate must be retained as a raw/axis sample, not silently ignored.
- [ ] Refactor `SensorController` to publish raw packet snapshots alongside decoded convenience state.
- [ ] Decide `CliffState` model:
  - Preferred: represent packet type `0x01` as `CliffContactState` with named bytes and a derived `motionAllowed`.
  - Keep `MotionController` safety based on `motionAllowed`, not raw `rawValue != 0`.
- [ ] Update docs with exact mapping confidence:
  - verified
  - inferred
  - unknown
- [ ] Verify:
  - `swift test --package-path Packages/LooiKit --filter SensorControllerTests`
  - `swift test --package-path Packages/LooiKit`

**Exit criteria:**

- Motion safety no longer depends on a misleading one-byte bitfield assumption.
- Test fixtures preserve actual hardware packets.
- Docs and code use the same packet model.

---

## Slice 2: Hardware Smoke Checklist

**Goal:** Turn DevTools hardware bring-up into a repeatable M1 verification protocol.

**Files:**

- Create: `docs/m1-smoke-test-checklist.md`
- Modify: `ulooi/DevTools/Probe/LogsView.swift`
- Modify: `ulooi/Shared/BuildInfo.swift`
- Optional modify: `ulooi/DevTools/ConnectionBanner.swift`

**Tasks:**

- [ ] Add an 8-step checklist:
  - build identity visible
  - BLE poweredOn
  - scan finds Looi
  - connect reaches `.ready`
  - heartbeat tick count increases
  - battery poll updates
  - STOP write works
  - disconnect sends emergency stop and clears ready state
- [ ] Add a checklist section for physical safety:
  - Looi on ground before motion tests
  - verify cliff lockout by lifting front only after STOP
  - log exact packet annotation in Sense tab
- [ ] Add log export instructions:
  - copy Logs tab
  - attach Xcode console excerpts when OSLog has raw packet details
- [ ] Update `BuildInfo.label` before hardware runs.
- [ ] Verify:
  - `swift test --package-path Packages/LooiKit`
  - `xcodebuild build -project ulooi.xcodeproj -scheme ulooi -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -quiet`
  - manual real-device run on iPhone, because BLE does not work meaningfully in simulator

**Exit criteria:**

- Any future agent/human can reproduce a real-Looi smoke pass without reconstructing tribal knowledge.
- Hardware observations feed back into fixture updates instead of ad hoc comments.

---

## Slice 3: GestureLibrary Foundation

**Goal:** Add a safe, testable GestureLibrary over the existing controllers.

**Prerequisite:** Slice 1 must be merged.

**Files:**

- Create: `Packages/LooiKit/Sources/LooiKit/Gestures/GestureLibrary.swift`
- Create: `Packages/LooiKit/Sources/LooiKit/Gestures/GestureKind.swift`
- Modify: `Packages/LooiKit/Sources/LooiKit/Session/LooiSession.swift`
- Create: `Packages/LooiKit/Tests/LooiKitTests/GestureLibraryTests.swift`
- Modify: `ulooi/DevTools/Probe/CommandView.swift`

**Tasks:**

- [ ] Define `GestureKind`: `wave`, `lookAtMe`, `dance`, `patrol`, `sleep`, `celebrate`.
- [ ] Implement actor serialization: only one gesture in flight; starting a new gesture cancels the current one.
- [ ] Implement safe gestures first:
  - `wave`: head up, blink light, center
  - `lookAtMe`: head up, light half
  - `sleep`: stop, head down, light off
- [ ] Implement ground-required gestures after cliff truth is stable:
  - `dance`
  - `patrol`
- [ ] Add DevTools buttons under Command tab.
- [ ] Verify:
  - gesture cancellation sends stop/light cleanup best-effort.
  - cliff-locked dance/patrol throws and does not mutate motion.
  - `swift test --package-path Packages/LooiKit --filter GestureLibraryTests`
  - full `swift test --package-path Packages/LooiKit`

**Exit criteria:**

- Agent-facing future API exists as `await session.gestures.wave()` style behavior.
- DevTools can test gestures without production UI.

---

## Slice 4: Production Shell

**Goal:** Replace DevTools root with first family-visible M1 app shell while preserving DevTools under Settings.

**Prerequisite:** Slice 3 should be merged or close to merged.

**Files:**

- Modify: `ulooi/ContentView.swift`
- Create: `ulooi/Main/RootModeView.swift`
- Create: `ulooi/Main/EmbodiedMainView.swift`
- Create: `ulooi/Main/StandaloneView.swift`
- Create: `ulooi/Main/GestureRingOverlay.swift`
- Create: `ulooi/Main/DriveSheet.swift`
- Create: `ulooi/Settings/SettingsRootView.swift`
- Move or reference: `ulooi/DevTools/DevToolsRootView.swift`
- Create or update: UI tests if target exists; otherwise document manual simulator QA

**Tasks:**

- [ ] Run gstack `/plan-design-review` before implementation.
- [ ] Define mode selection:
  - `.ready` + landscape → embodied mode
  - not ready or portrait → standalone placeholder / reconnect affordance
- [ ] Build embodied mode:
  - status pill
  - gesture ring
  - drive sheet
  - face placeholder or geometric face depending current scope
- [ ] Move DevTools entry to Settings → Developer.
- [ ] Preserve cold-launch auto-reconnect from `LooiBootstrap`.
- [ ] Verify with simulator screenshots:
  - portrait disconnected
  - landscape connected mock state if feasible
  - Settings → Developer opens old DevTools
- [ ] Run gstack `/design-review` after screenshots.

**Exit criteria:**

- First screen is no longer a lab tool.
- DevTools remains accessible.
- UI does not claim UCLAW/voice capability before M2/M3.

---

## Slice 5: M2 UCLAW Contract Plan

**Goal:** Plan the first cross-repo UCLAW integration without entangling git histories.

**Prerequisite:** M1 shell direction accepted.

**Repos:**

- ulooi: `/Users/ryanliu/Documents/uclaw/ulooi`
- UCLAW: `/Users/ryanliu/Documents/uclaw`

**Tasks:**

- [ ] In `ulooi`, write `docs/superpowers/plans/YYYY-MM-DD-m2-uclaw-transport-client.md`.
- [ ] In UCLAW repo, write matching backend plan for RemoteBridgeService.
- [ ] Define envelope schema source-of-truth:
  - where CDDL lives
  - how Swift/Rust generation is checked
  - how drift is detected in CI
- [ ] Define pairing:
  - QR payload
  - token lifetime
  - key storage
  - rolling renewal
- [ ] Define dev loop:
  - mock UCLAW server for ulooi tests
  - mock ulooi client for UCLAW tests
  - manual LAN/Tailscale smoke path
- [ ] Run gstack `/plan-eng-review` on both plans before code.

**Exit criteria:**

- No M2 code begins until both repos agree on envelope, pairing, and test strategy.
- Each repo has independent branches and independent verification commands.

---

## Recommended Immediate Next Prompt

Use this prompt to begin Slice 1:

```text
请执行 docs/superpowers/plans/2026-05-18-ulooi-next-step-stack.md 的 Slice 1: Sensor Truth Replay。

约束：
- 只改 ulooi repo，不碰 /Users/ryanliu/Documents/uclaw 这个 UCLAW repo。
- 先写 FED9/FED8 replay fixtures 和失败测试，再改 SensorController。
- 不要做生产 UI、GestureLibrary、UCLAW transport。
- 最终必须跑：
  swift test --package-path Packages/LooiKit --filter SensorControllerTests
  swift test --package-path Packages/LooiKit
- 最终报告必须列出：修改文件、测试结果、仍未验证的硬件语义。
```

## Review Gate Before Coding

Before starting Slice 1, run one of:

- Lightweight: `superpowers:executing-plans` against this plan.
- Full gstack pass: `/autoplan` on this plan, then accept/reject its recommended changes.

My recommendation: start with Slice 1 directly, then run `/review` after the patch. Save `/autoplan` for Slice 4 or Slice 5 where product/design/architecture tradeoffs are larger.
