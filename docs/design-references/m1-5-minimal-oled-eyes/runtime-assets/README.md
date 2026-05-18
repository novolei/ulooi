# Runtime Face Assets

**Status:** First playable image-generated assets for M1.5 Minimal OLED Eyes.
**Source:** Generated from the approved concept direction in `../README.md`.

These PNGs are app-bundled runtime candidates, not final designer-owned master assets.
Each runtime PNG is normalized to `2796x1290` on a pure black canvas for iPhone landscape Face mode.

## Assets

| Asset | Runtime state |
|---|---|
| `face_idle` | Default awake/idle face |
| `face_happy` | Touch and friendly gesture response |
| `face_sleepy` | Sleep gesture and sleeping state |
| `face_cautious` | Suspended/safety/error caution |
| `face_offline` | Disconnected or looking for body |
| `face_blink` | Short idle blink transition |

## Constraints

- Pure black OLED background.
- Content inside landscape iPhone safe area.
- Mostly cyan eyes.
- No robot shell, white background, outer border, or large decorative aura.
