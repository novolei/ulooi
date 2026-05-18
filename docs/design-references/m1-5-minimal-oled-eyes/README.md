# M1.5 Face Engine — Minimal OLED Eyes Direction

**Status:** Approved concept direction, 2026-05-19
**Asset role:** Design reference and generation target, not final bundled runtime assets yet.
**Origin:** Codex image generation during Face mode brainstorm.
**Repo boundary:** this folder belongs to `/Users/ryanliu/Documents/uclaw/ulooi`. The paired UCLAW repo is `/Users/ryanliu/Documents/uclaw`; the two repos are managed separately.

---

## Decision

ulooi Face mode should move from a Canvas-drawn geometric face toward an **image-generated asset-first** style:

- Landscape iPhone Face mode uses a pure black OLED field.
- The face is mostly two glowing cyan eyes.
- Mouth, glasses, brows, blush, symbols, and tiny accents are optional per state.
- No robot shell, no white background, no device mockup, no outer border, no decorative oval aura.
- All visible content must sit inside the iPhone landscape safe area with generous margins for rounded corners and Dynamic Island avoidance.

The selected direction is intentionally minimal. ulooi should feel like a small future family member living inside the phone screen, not like a generic sticker pack or a busy sci-fi HUD.

## Approved Reference

| File | Purpose |
|---|---|
| `00-approved-concept-sheet.png` | Approved multi-state direction: simple cyan OLED eyes with minimal state-specific accessories. |

## Visual Grammar

### Always

- Background: solid black OLED, `#000000` or visually equivalent.
- Main identity: two cyan glowing eyes.
- Composition: centered, spacious, landscape-first.
- Styling: simple LED/anime robot expression language.
- Personality: cute, clever, warm, witty, family-companion, slightly futuristic.

### Sometimes

- Tiny mouth for happy, surprised, sleepy, or embarrassed states.
- Thin glasses outline for focused/thinking states.
- Small blush dots for happy/touched states.
- Small symbol accents for curious/searching states.
- Safety brows or alert ticks for suspended/caution states.

### Never

- Robot body or head shell.
- White background.
- Phone mockup, bezel, frame, card, or border.
- Large halo, oval face enclosure, particles, ambient scene, or busy background.
- Human/animal facial features.
- Text, labels, logos, or watermarks.

## State Coverage

M1.5 should generate production-ready variants for the existing `FaceExpression` and `PresenceState` vocabulary:

| Product state | Face variant | Notes |
|---|---|---|
| `idle` / `awake` | calm oval eyes | Default identity. Slow breathing and rare blink can be runtime-driven. |
| `happy` / `touched` | crescent eyes, optional blush/mouth | Fast delight, then return to idle. |
| `looking` / `lookAtMe` | attentive eyes, gaze offset | Eye position and scale can vary for up/down/left/right. |
| `surprised` | rounder eyes, tiny mouth | Used for touch or unexpected sensor events. |
| `sleepy` / `sleeping` | half-lid or closed eyes | Minimal mouth, slower glow. |
| `cautious` / `suspended` | narrowed eyes, safety brow accents | Clear but not alarming; physical movement remains locked. |
| `focused` | glasses mode | Use for future thinking/listening/agent intent. |
| `offline` / `lookingForBody` | dimmed eyes, optional small search accent | No complex radar scene. |

## Asset Strategy

Use image generation to produce the visual identity and state variants, then use SwiftUI only to present and choreograph assets:

1. Generate a canonical idle face.
2. Generate state variants from the canonical identity, preserving eye spacing, glow weight, color, and safe-area margins.
3. Export each state as a landscape PNG asset.
4. Optional later refinement: split eyes/mouth/accessory/glow into layers, but do not require that for the first playable slice.
5. Runtime animation should be lightweight: opacity crossfade, small scale, eye offset, blink frame swap, breathing glow, and weighted random state selection.

This means Canvas should no longer be the source of visual truth for the face. It can be retired or kept only as a developer/debug fallback while the production renderer uses image assets.

## Prompt Template

Use this as the base prompt for future generations:

```text
Generate a full-screen ulooi Face Mode image for iPhone landscape orientation, aspect ratio 19.5:9. Solid pure black OLED background across the entire image. No device frame, no border, no bezel, no mockup, no card, no panels, no robot body, no robot head shell, no white background, no outer oval halo, no decorative atmosphere. Only show the facial expression elements floating on black: mostly two simple glowing cyan LED anime robot eyes, centered safely within an imaginary iPhone rounded-screen safe area with generous margins. Style: minimal OLED eyes, cute futuristic robot companion, clever, warm, witty, family member. Add only the minimal state-specific accessory if useful: tiny mouth, thin glasses, tiny blush, small brow accent, or small symbol. Keep identity consistent with the canonical idle face. No text, no logo, no watermark.
```

State-specific suffix examples:

- Idle: `calm oval eyes, relaxed awake presence, no accessory.`
- Happy touched: `closed crescent eyes, tiny smile, very subtle rose blush dots.`
- Focused: `oval eyes plus thin cyan glasses outline, attentive and smart.`
- Sleepy: `half-lid sleepy eyes, tiny relaxed mouth, lower brightness.`
- Cautious: `slightly narrowed eyes, tiny safety brow accents, no alarm graphics.`

## Implementation Notes

- Put production assets under `ulooi/Main/Face/Assets/` or a dedicated asset catalog group, not under docs.
- Introduce a renderer boundary such as `FaceAssetRendering` / `FaceAnimationSelecting`.
- Keep `FaceModel` as the semantic state mapper; do not let views know BLE details.
- Prefer `@Observable` view models and SwiftUI composition.
- Keep files small and role-based: models, selector, renderer, views, assets.
- Do not expand `GeometricFaceView.swift` into a god file.
