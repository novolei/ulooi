# ulooi

**iOS app that gives the [UCLAW](https://github.com/novolei/uclaw-new) Agent an embodied presence through the Looi robot.**

> iPhone is the sensory surface (mic / camera / speaker).
> Looi robot is the kinetic body (motion / light / touch).
> UCLAW desktop is the Cortex (reasoning / memory / tools).
> ulooi is the Reflex (instant response + offline degradation).

---

## Status

| Milestone | What | State |
|---|---|---|
| **M0** | Umbrella spec | ✅ approved — see [`2026-05-17-ulooi-design.md`](https://github.com/novolei/uclaw-new/blob/main/docs/superpowers/specs/2026-05-17-ulooi-design.md) (canonical, lives in UCLAW repo) |
| **M0.5** | Hardware reachability prototype (probe app — DevTools surface) | 🚧 in progress — scaffold ready, hardware probe pending. See [`docs/m0-5-prototype-findings.md`](docs/m0-5-prototype-findings.md). |
| **M1** | LooiKit + iOS shell + pairing UX (no UCLAW dep) | pending |
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

## Documentation

- [`docs/prd.md`](docs/prd.md) — Product Requirements Document (personas, user stories, UX flows, success metrics)
- [`docs/architecture.md`](docs/architecture.md) — Overall architecture (tech stack, module layering, data model, protocol codegen, file structure)
- [M0 umbrella spec](https://github.com/novolei/uclaw-new/blob/main/docs/superpowers/specs/2026-05-17-ulooi-design.md) (cross-project program design, lives in UCLAW repo)

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

**Current state (M0.5):** The app boots directly into the **DevTools probe surface** — a 5-tab tool for reverse-engineering Looi's BLE protocol against the current firmware. Tabs: Scan / Inspect / Send / Sense / Logs. In M1 this will be demoted to Settings → Developer, and the production UI will take over the root.

Probe findings are recorded in [`docs/m0-5-prototype-findings.md`](docs/m0-5-prototype-findings.md) as you go; the doc becomes input to the M1 LooiKit spec.

### Module layout (M0.5)

```
ulooi/ulooi/
├── ulooiApp.swift / ContentView.swift   — app entry, routes to DevTools
├── DevTools/                            — probe surface (Settings → Developer in M1)
│   ├── DevToolsRootView.swift           — TabView container
│   └── Probe/
│       ├── ScanView.swift               — BLE peripheral scanner
│       ├── InspectView.swift            — GATT topology browser
│       ├── CommandView.swift            — send raw bytes / preset commands
│       ├── SenseView.swift              — subscribe to notify characteristics
│       ├── LogsView.swift               — live RAW / INFO / WARN / ERR log viewer
│       └── ProbeLog.swift               — shared logging
└── LooiKit/                             — early skeleton (will move to Packages/LooiKit in M1)
    ├── BLECentral.swift                 — CoreBluetooth wrapper (@MainActor @Observable)
    └── LooiCommand.swift                — reference command dict (UNVERIFIED in M0.5)
```

## License

TBD before M1 ships.

## Acknowledgements

BLE protocol references:

- [andrey-tut/LOOI-Robot](https://github.com/andrey-tut/LOOI-Robot) — protocol reverse engineering
- [splattydoesstuff/sooperchargeforbots](https://github.com/splattydoesstuff/sooperchargeforbots) — Looi mod tooling
