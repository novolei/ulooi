# ulooi M1.5 — Minimal OLED Face Animation Design

**Status:** Approved direction, 2026-05-19
**Program:** ulooi — iOS embodiment of UCLAW Agent through Looi robot
**Predecessor:** `2026-05-18-ulooi-presence-slice-design.md`
**Related reference:** `docs/design-references/m1-5-minimal-oled-eyes/`
**Scope:** Product/design spec only. Implementation plan follows after review.
**Repo boundary:** this spec belongs to `/Users/ryanliu/Documents/uclaw/ulooi`; the paired UCLAW repo is `/Users/ryanliu/Documents/uclaw`. They are separate git repositories and must be managed separately.

---

## 1. Decision

ulooi Face mode should use an **image-generated asset-first** face system instead of treating SwiftUI Canvas drawing as the production visual source.

The selected visual direction is:

> Minimal OLED Eyes: pure black landscape iPhone face stage, two cyan glowing eyes as the identity core, and tiny state-specific accessories only when they improve expression.

This replaces the previous direction of a geometric Canvas face and also supersedes the older yellow chibi reference direction for M1.5. Canvas can remain as a temporary fallback/debug renderer, but production Face mode should be driven by curated image assets plus lightweight SwiftUI choreography.

## 2. Product Goal

The first goal is not to show "a nice image." The goal is to make the connected Looi body feel awake:

- The phone face is visually alive when mounted on the Looi base.
- The face reads clearly from across a room.
- The design feels like a clever future family companion, not a generic robot UI.
- The animation system is stateful and calm, not random noise.
- Face reactions coordinate with Presence state, gestures, light, and head/motion commands.

## 3. Visual Rules

### 3.1 Canvas

The runtime should not use Canvas to draw production eyes, mouth, glow, or expression geometry. This avoids spending engineering time hand-tuning shapes that should be art-directed through generated and curated assets.

Allowed Canvas-like behavior:

- Debug fallback if assets are missing.
- Temporary placeholder during development.
- Lightweight masks or overlays only if they do not become the visual source of truth.

### 3.2 Image Assets

Production Face mode should display generated or designer-refined PNG assets:

- Pure black background.
- Landscape iPhone aspect, initially 19.5:9 compatible.
- Content safely inside rounded-screen safe area.
- Minimal cyan OLED expression elements.
- No phone frame, no outer border, no robot body, no white sheet, no halo scene.

Generated assets are acceptable for the first implementation slice if they are curated and consistent. Later, a human designer can refine them into layered source files without changing the renderer contract.

## 4. State Catalog

M1.5 should start with a compact state catalog:

| Variant | Trigger source | Visual behavior |
|---|---|---|
| `idle` | `.awake`, `.idle` | Two calm oval cyan eyes, slow breathing opacity, rare blink. |
| `happy` | `.touched`, successful gesture completion | Crescent eyes, optional tiny smile/blush, short dwell. |
| `curious` | looking/searching, future listening | Slight asymmetry, optional tiny question accent. |
| `surprised` | sudden touch or event | Rounder eyes, tiny mouth, quick recovery. |
| `sleepy` | `.sleeping` | Half-lid or closed eyes, dim glow, very slow rhythm. |
| `cautious` | `.suspended`, cliff/safety | Narrowed eyes, tiny brow/safety accent, no playful randomness. |
| `focused` | future agent thinking/listening | Thin glasses mode, calm attention. |
| `offline` | `.disconnected`, `.lookingForBody` | Dimmed eyes, minimal search accent. |
| `blink` | transient animation frame | Thin horizontal eyes for 50-120ms. |
| `wink` | rare idle/touched flourish | One eye closed, low probability. |

The catalog can expand later, but the first slice should avoid too many variants before identity consistency is proven on a real iPhone.

## 5. Randomness Strategy

Randomness should make ulooi feel alive, not unstable.

Rules:

- Random only inside state-appropriate variant pools.
- Safety, suspended, disconnected, and error states must be deterministic or near-deterministic.
- Idle can use low-probability micro variants such as blink, glance, and wink.
- Touched can choose among 2-3 happy/surprised variants.
- A selected variant should have a minimum dwell time to avoid flicker.
- Use weighted randomness with cooldowns for rare flourishes.

Suggested first weights:

| State | Primary | Secondary | Rare |
|---|---:|---:|---:|
| Idle | 82% idle | 15% blink/glance | 3% wink |
| Touched | 65% happy | 25% surprised | 10% blush |
| Sleepy | 90% sleepy | 10% blink | 0% |
| Cautious | 100% cautious | 0% | 0% |
| Offline | 85% offline | 15% search | 0% |

## 6. Proposed Architecture

Keep the semantic model separate from rendering:

```text
PresenceState
  -> FaceModel
    -> FaceAnimationSelector
      -> FaceAssetVariant
        -> ImageFaceRenderer
```

### 6.1 `FaceModel`

Current `FaceModel` should remain the semantic mapper from `PresenceState` to expression, gaze, glow, and copy. It should not load assets and should not know image filenames.

### 6.2 `FaceAnimationSelector`

New selector responsibility:

- Accept `FaceModel`, current time, and optional random source.
- Choose a `FaceAssetVariant`.
- Respect dwell time, cooldowns, and safety determinism.
- Be unit-testable with a deterministic RNG.

### 6.3 `FaceAssetVariant`

Small model describing renderable assets:

- `id`
- `expression`
- `assetName`
- `duration`
- `transition`
- `allowsMicroMotion`
- `priority`

### 6.4 `ImageFaceRenderer`

SwiftUI renderer responsibility:

- Load the selected asset from app resources.
- Fit it full-screen landscape with black background.
- Preserve safe-area composition.
- Apply lightweight transitions only: opacity, tiny scale, tiny offset, brightness.
- Avoid Canvas drawing for the production face.

### 6.5 `GeometricFaceView`

Existing `GeometricFaceView` can remain temporarily as:

- Debug fallback.
- A migration reference.
- A target for removal once image assets are stable.

It should not receive new production expression logic.

## 7. File Organization

Recommended structure:

```text
ulooi/Main/Face/
  Models/
    FaceAssetVariant.swift
    FaceAnimationState.swift
  Engine/
    FaceAnimationSelector.swift
    FaceRandomSource.swift
  Views/
    ImageFaceRenderer.swift
    FaceStageView.swift
  Assets/
    FaceAssetCatalog.swift
```

This follows the project requirement to avoid god files and keep modules role-based.

## 8. Asset Pipeline

1. Use the approved concept sheet as the style target.
2. Generate a canonical idle image first.
3. Generate variants from the canonical identity.
4. Store raw references under `docs/design-references/`.
5. Store production app assets only after curation under app resource paths.
6. Add a small README documenting prompts, state mapping, and known limitations.
7. Verify on real iPhone landscape before treating a variant as production-ready.

## 9. First Implementation Slice

The next development slice should be narrow:

1. Add app-bundled placeholder assets for `idle`, `happy`, `sleepy`, `cautious`, `offline`, and `blink`.
2. Implement `FaceAnimationSelector` with deterministic tests.
3. Replace production Face mode renderer with `ImageFaceRenderer`.
4. Keep DevTools or debug flag able to show the old geometric fallback.
5. Verify the face on simulator and real device in landscape.

Out of scope for the first slice:

- Full video animation.
- Per-frame sprite sheets for every state.
- Layered PSD/Figma pipeline.
- UCLAW chat/listening face states.
- Audio lipsync.

## 10. Self-Review

- **Architecture:** The design preserves existing Presence semantics and adds a selector/renderer boundary instead of enlarging a single SwiftUI file.
- **Product fit:** The selected visual language matches Ryan's approved direction: mostly eyes, pure black, optional tiny accessories, cute and futuristic.
- **Performance:** Image display plus lightweight SwiftUI transitions is safer than heavy per-frame generated animation or runtime shape drawing.
- **Risk:** AI-generated variants may drift in spacing or style. Mitigation: canonical idle first, variant generation from that identity, deterministic catalog review before bundling.
- **Next action:** Write an implementation plan for the first image-based Face mode slice.
