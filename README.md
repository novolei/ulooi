# ulooi

**iOS app that gives the UCLAW Agent an embodied presence through the Looi robot.**

> iPhone is the sensory surface (mic / camera / speaker).
> Looi robot is the kinetic body (motion / light / touch).
> UCLAW desktop is the Cortex (reasoning / memory / tools).
> ulooi is the Reflex (instant response + offline degradation).

---

## Status

| Milestone | What | State |
|---|---|---|
| **M0** | Umbrella spec | ✅ approved — canonical program design lives in the companion UCLAW repo/workspace |
| **M0.5** | Hardware reachability prototype (probe app — DevTools surface) | ✅ completed against real Looi hardware. See [`docs/m0-5-prototype-findings.md`](docs/m0-5-prototype-findings.md). |
| **M1 PR1** | Extract `Packages/LooiKit`, typed session/controllers, mock transport | ✅ implemented; `swift test --package-path Packages/LooiKit` passes |
| **M1 PR2/PR3** | Production shell, gestures, face/dreams surface, Settings → Developer | pending |
| **M2** | UCLAW transport layer (WebSocket + pairing) | pending |
| **M3** | Voice loop (S1 体验) | pending |
| **M4** | Three-way presence (S2 体验) | pending |
| **M5** | Reflex layer + offline degradation | pending |
| **M6** | Vision | P1 |
| **M7** | Speaker identification | P1 |
| **M8** | Memory write-back to UCLAW memory_graph | P1 |

## Architecture (one-pager)

```
iPhone (SENSORY + REFLEX + LooiKit)
   ↕  BLE (commands + sensor telemetry, no audio)
Looi robot (motion / light / touch)

iPhone
   ↕  CBOR over WebSocket (LAN-first, Tailscale fallback)
UCLAW desktop (CORTEX: Agent + LLM + memory_graph + MCP + skills)
```

Audio (mic + speaker) and vision (camera) run on the iPhone natively; the Looi robot does **not** carry audio/video. Lip-sync illusion comes from coordinating TTS playback with BLE light-pulse / motion-micro commands.

Full design in the [M0 umbrella spec](https://github.com/novolei/uclaw-new/blob/main/docs/superpowers/specs/2026-05-17-ulooi-design.md).

## Repository boundary

`ulooi` and `UCLAW` are separate git repositories. Do not share branches, commits, or PR scopes across them.

- This repo: `/Users/ryanliu/Documents/uclaw/ulooi`
- Companion UCLAW workspace/repo family: `/Users/ryanliu/Documents/uclaw`
- When working on ulooi/UCLAW integration, treat the UCLAW repo under that workspace as the corresponding backend/cortex source of truth, not older similarly named UClaw paths.

## Documentation

- [`docs/prd.md`](docs/prd.md) — Product Requirements Document (personas, user stories, UX flows, success metrics)
- [`docs/architecture.md`](docs/architecture.md) — Overall architecture (tech stack, module layering, data model, protocol codegen, file structure)
- M0 umbrella spec (cross-project program design, lives in the companion UCLAW repo/workspace)

iOS implementation: **Pure SwiftUI / Swift**, no Rust on iOS. Protocol consistency with UCLAW achieved via [CDDL](https://datatracker.ietf.org/doc/html/rfc8610) schema codegen (a single source spec generates both Swift `Codable` types and Rust serde structs). See [architecture §2](docs/architecture.md#2-技术栈选择) for rationale.

## Requirements

- Xcode 16+
- iOS 18.2+ (for Apple Foundation Model in the reflex layer)
- A Looi robot ([Indiegogo](https://www.indiegogo.com/projects/looi-turn-your-phone-into-a-cute-robot--2))
- UCLAW desktop running (required from M2 onward)

## Development

```bash
xed ulooi.xcodeproj    # open in Xcode 16+
# Cmd+R to build & run on a real iPhone (BLE doesn't work in simulator)
```

**Current state:** The app still boots directly into the **DevTools probe surface**, but the probe now drives the M1 `LooiSession` / controller stack instead of the old inline `BLECentral`. Tabs: Scan / Inspect / Send / Sense / Logs. In a later M1 shell PR this surface will move to Settings → Developer, and the production face/gesture UI will take over the root.

Probe findings are recorded in [`docs/m0-5-prototype-findings.md`](docs/m0-5-prototype-findings.md) and have already been folded into the current `Packages/LooiKit` foundation.

### Module layout (current)

```
ulooi/
├── ulooi.xcodeproj/
├── ulooi/
│   ├── ulooiApp.swift / ContentView.swift      — app entry, currently routes to DevTools
│   ├── App/LooiBootstrap.swift                 — app singleton wiring CoreBluetoothTransport + LooiSession
│   ├── DevTools/                               — probe surface (future Settings → Developer)
│   │   ├── DevToolsRootView.swift              — TabView container
│   │   └── Probe/
│   │       ├── ScanView.swift                  — BLE peripheral scanner + LooiSession connect
│   │       ├── InspectView.swift               — session/controller state
│   │       ├── CommandView.swift               — Motion/Head/Light controller commands
│   │       ├── SenseView.swift                 — decoded FED5/FED9 sensor surface
│   │       ├── LogsView.swift                  — live INFO/WARN/ERR log viewer
│   │       └── ProbeLog.swift                  — shared in-app logging
│   └── Shared/                                 — app-only logging/build metadata
└── Packages/LooiKit/
    ├── Sources/LooiKit/
    │   ├── Protocol/                           — UUIDs, timing, FEDA handshake runner
    │   ├── Transport/                          — BLETransport + CoreBluetoothTransport
    │   ├── Session/                            — LooiSession, state machine, reconnect policy
    │   ├── Controllers/                        — Motion, Head, Light, Sensor
    │   ├── Commands/                           — typed BLE command bytes
    │   ├── Models/                             — MotionState, CliffState, etc.
    │   └── Errors/                             — LooiError
    ├── Sources/LooiKitTesting/                 — MockBLETransport + test helpers
    └── Tests/LooiKitTests/                     — package unit tests
```

## License

TBD before M1 ships.

## Acknowledgements

BLE protocol references:

- [andrey-tut/LOOI-Robot](https://github.com/andrey-tut/LOOI-Robot) — protocol reverse engineering
- [splattydoesstuff/sooperchargeforbots](https://github.com/splattydoesstuff/sooperchargeforbots) — Looi mod tooling
