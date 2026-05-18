# ulooi Minimal OLED Face Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the production Face mode visual source with image-generated Minimal OLED Eyes assets while keeping Presence semantics and DevTools fallback intact.

**Architecture:** Keep `PresenceState` and `FaceModel` as semantic truth. Add a small face asset catalog, deterministic animation selector, and SwiftUI image renderer under `ulooi/Main/Face/`; `GeometricFaceView` remains only as a debug/fallback renderer. The first slice ships static generated assets plus lightweight SwiftUI transition/micro-motion, not Canvas-drawn production eyes.

**Tech Stack:** SwiftUI, Observation-compatible value models, Xcode asset catalog PNG resources, deterministic RNG seam for tests/manual inspection, existing `LooiKit`/Presence app layer.

---

## File Structure

Create or modify these files:

- Create: `ulooi/Main/Face/Models/FaceAssetVariant.swift` — renderable face asset metadata.
- Create: `ulooi/Main/Face/Models/FaceRenderMode.swift` — production image vs debug geometric fallback.
- Create: `ulooi/Main/Face/Engine/FaceRandomSource.swift` — deterministic random seam for selector tests and predictable debug.
- Create: `ulooi/Main/Face/Engine/FaceAnimationSelector.swift` — maps `FaceModel` to weighted face asset variants with dwell/cooldown.
- Create: `ulooi/Main/Face/Assets/FaceAssetCatalog.swift` — central names for bundled image assets.
- Create: `ulooi/Main/Face/Views/ImageFaceRenderer.swift` — production renderer for image assets.
- Create: `ulooi/Main/Face/Views/FaceStageView.swift` — selects image renderer or geometric fallback.
- Modify: `ulooi/Main/EmbodiedHomeView.swift` — replace direct `GeometricFaceView` usage with `FaceStageView`.
- Create: `ulooi/Assets.xcassets/FaceAssets/<state>.imageset/` — first generated PNG states.
- Create: `docs/design-references/m1-5-minimal-oled-eyes/runtime-assets/README.md` — records asset source/prompt/usage.
- Modify: `docs/m1-2-presence-smoke-test-checklist.md` — add Face mode visual QA items.

Do not modify `/Users/ryanliu/Documents/uclaw`; this plan belongs only to the nested `ulooi` git repo.

---

### Task 1: Generate and Bundle First Runtime Face Assets

**Files:**
- Create: `ulooi/Assets.xcassets/FaceAssets/Contents.json`
- Create: `ulooi/Assets.xcassets/FaceAssets/face_idle.imageset/Contents.json`
- Create: `ulooi/Assets.xcassets/FaceAssets/face_happy.imageset/Contents.json`
- Create: `ulooi/Assets.xcassets/FaceAssets/face_sleepy.imageset/Contents.json`
- Create: `ulooi/Assets.xcassets/FaceAssets/face_cautious.imageset/Contents.json`
- Create: `ulooi/Assets.xcassets/FaceAssets/face_offline.imageset/Contents.json`
- Create: `ulooi/Assets.xcassets/FaceAssets/face_blink.imageset/Contents.json`
- Create: `docs/design-references/m1-5-minimal-oled-eyes/runtime-assets/README.md`

- [x] **Step 1: Generate six PNG assets from the approved prompt family**

Use the approved Minimal OLED Eyes visual grammar from `docs/design-references/m1-5-minimal-oled-eyes/README.md`.

Generate these six landscape PNGs:

| Asset name | Prompt suffix |
|---|---|
| `face_idle.png` | `calm oval cyan eyes, relaxed awake presence, no accessory.` |
| `face_happy.png` | `closed crescent cyan eyes, tiny smile, very subtle rose blush dots.` |
| `face_sleepy.png` | `half-lid sleepy cyan eyes, tiny relaxed mouth, lower brightness.` |
| `face_cautious.png` | `slightly narrowed cyan eyes, tiny safety brow accents, no alarm graphics.` |
| `face_offline.png` | `dimmed cyan-gray oval eyes, tiny search accent, quiet disconnected feeling.` |
| `face_blink.png` | `two short thin cyan horizontal eyes, transient blink frame, no mouth.` |

Every generated image must keep these constraints:

```text
Generate a full-screen ulooi Face Mode image for iPhone landscape orientation, aspect ratio 19.5:9. Solid pure black OLED background across the entire image. No device frame, no border, no bezel, no mockup, no card, no panels, no robot body, no robot head shell, no white background, no outer oval halo, no decorative atmosphere. Only show facial expression elements floating on black: mostly two simple glowing cyan LED anime robot eyes, centered safely within an imaginary iPhone rounded-screen safe area with generous margins. Style: minimal OLED eyes, cute futuristic robot companion, clever, warm, witty, family member. No text, no logo, no watermark.
```

- [x] **Step 2: Copy generated images into asset catalog**

Copy files into:

```text
ulooi/Assets.xcassets/FaceAssets/face_idle.imageset/face_idle.png
ulooi/Assets.xcassets/FaceAssets/face_happy.imageset/face_happy.png
ulooi/Assets.xcassets/FaceAssets/face_sleepy.imageset/face_sleepy.png
ulooi/Assets.xcassets/FaceAssets/face_cautious.imageset/face_cautious.png
ulooi/Assets.xcassets/FaceAssets/face_offline.imageset/face_offline.png
ulooi/Assets.xcassets/FaceAssets/face_blink.imageset/face_blink.png
```

Create `ulooi/Assets.xcassets/FaceAssets/Contents.json`:

```json
{
  "info": {
    "author": "xcode",
    "version": 1
  }
}
```

Create each imageset `Contents.json` with the matching filename:

```json
{
  "images": [
    {
      "filename": "face_idle.png",
      "idiom": "universal"
    }
  ],
  "info": {
    "author": "xcode",
    "version": 1
  }
}
```

Repeat with the correct filename for each state.

- [x] **Step 3: Document asset provenance**

Create `docs/design-references/m1-5-minimal-oled-eyes/runtime-assets/README.md`:

```markdown
# Runtime Face Assets

**Status:** First playable image-generated assets for M1.5 Minimal OLED Eyes.
**Source:** Generated from the approved concept direction in `../README.md`.

These PNGs are app-bundled runtime candidates, not final designer-owned master assets.

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
```

- [x] **Step 4: Verify asset catalog is visible to Xcode**

Run:

```bash
xcodebuild build -project ulooi.xcodeproj -scheme ulooi -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -quiet
```

Expected: build succeeds. If Xcode reports a malformed asset catalog, fix the `Contents.json` filename entries.

- [x] **Step 5: Commit**

```bash
git add ulooi/Assets.xcassets/FaceAssets docs/design-references/m1-5-minimal-oled-eyes/runtime-assets/README.md
git commit -m "feat(face): add minimal OLED runtime assets"
```

---

### Task 2: Add Face Asset Catalog and Variant Models

**Files:**
- Create: `ulooi/Main/Face/Models/FaceAssetVariant.swift`
- Create: `ulooi/Main/Face/Models/FaceRenderMode.swift`
- Create: `ulooi/Main/Face/Assets/FaceAssetCatalog.swift`

- [ ] **Step 1: Create `FaceAssetVariant`**

Create `ulooi/Main/Face/Models/FaceAssetVariant.swift`:

```swift
import Foundation

struct FaceAssetVariant: Equatable, Identifiable {
    enum Transition: Equatable {
        case immediate
        case crossfade(seconds: Double)
    }

    let id: String
    let expression: FaceExpression
    let assetName: String
    let minimumDwell: TimeInterval
    let transition: Transition
    let allowsMicroMotion: Bool
    let priority: Int
}
```

- [ ] **Step 2: Create render mode**

Create `ulooi/Main/Face/Models/FaceRenderMode.swift`:

```swift
enum FaceRenderMode: Equatable {
    case imageAssets
    case geometricFallback
}
```

- [ ] **Step 3: Create asset catalog names**

Create `ulooi/Main/Face/Assets/FaceAssetCatalog.swift`:

```swift
enum FaceAssetCatalog {
    static let idle = "face_idle"
    static let happy = "face_happy"
    static let sleepy = "face_sleepy"
    static let cautious = "face_cautious"
    static let offline = "face_offline"
    static let blink = "face_blink"

    static func primaryAssetName(for expression: FaceExpression) -> String {
        switch expression {
        case .idle, .looking:
            return idle
        case .happy, .surprised:
            return happy
        case .sleepy:
            return sleepy
        case .cautious:
            return cautious
        case .offline:
            return offline
        }
    }
}
```

- [ ] **Step 4: Build**

Run:

```bash
xcodebuild build -project ulooi.xcodeproj -scheme ulooi -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -quiet
```

Expected: build succeeds.

- [ ] **Step 5: Commit**

```bash
git add ulooi/Main/Face/Models/FaceAssetVariant.swift ulooi/Main/Face/Models/FaceRenderMode.swift ulooi/Main/Face/Assets/FaceAssetCatalog.swift
git commit -m "feat(face): model image face variants"
```

---

### Task 3: Add Deterministic Face Animation Selector

**Files:**
- Create: `ulooi/Main/Face/Engine/FaceRandomSource.swift`
- Create: `ulooi/Main/Face/Engine/FaceAnimationSelector.swift`

- [ ] **Step 1: Create random source seam**

Create `ulooi/Main/Face/Engine/FaceRandomSource.swift`:

```swift
import Foundation

protocol FaceRandomSource {
    mutating func nextDouble() -> Double
}

struct SystemFaceRandomSource: FaceRandomSource {
    mutating func nextDouble() -> Double {
        Double.random(in: 0..<1)
    }
}
```

- [ ] **Step 2: Create selector**

Create `ulooi/Main/Face/Engine/FaceAnimationSelector.swift`:

```swift
import Foundation

struct FaceAnimationSelector<Random: FaceRandomSource> {
    private var random: Random
    private var current: FaceAssetVariant?
    private var lastChange: Date?

    init(random: Random) {
        self.random = random
    }

    mutating func selectVariant(for model: FaceModel, now: Date) -> FaceAssetVariant {
        if let current, let lastChange, now.timeIntervalSince(lastChange) < current.minimumDwell {
            return current
        }

        let next = chooseVariant(for: model)
        current = next
        lastChange = now
        return next
    }

    private mutating func chooseVariant(for model: FaceModel) -> FaceAssetVariant {
        switch model.expression {
        case .idle:
            return random.nextDouble() < 0.12 ? .blink : .idle
        case .happy, .surprised:
            return .happy
        case .sleepy:
            return .sleepy
        case .cautious:
            return .cautious
        case .looking:
            return .idle
        case .offline:
            return .offline
        }
    }
}

extension FaceAssetVariant {
    static let idle = FaceAssetVariant(
        id: "idle",
        expression: .idle,
        assetName: FaceAssetCatalog.idle,
        minimumDwell: 2.8,
        transition: .crossfade(seconds: 0.22),
        allowsMicroMotion: true,
        priority: 0
    )

    static let happy = FaceAssetVariant(
        id: "happy",
        expression: .happy,
        assetName: FaceAssetCatalog.happy,
        minimumDwell: 1.4,
        transition: .crossfade(seconds: 0.16),
        allowsMicroMotion: true,
        priority: 1
    )

    static let sleepy = FaceAssetVariant(
        id: "sleepy",
        expression: .sleepy,
        assetName: FaceAssetCatalog.sleepy,
        minimumDwell: 4.0,
        transition: .crossfade(seconds: 0.35),
        allowsMicroMotion: false,
        priority: 1
    )

    static let cautious = FaceAssetVariant(
        id: "cautious",
        expression: .cautious,
        assetName: FaceAssetCatalog.cautious,
        minimumDwell: 2.5,
        transition: .crossfade(seconds: 0.16),
        allowsMicroMotion: false,
        priority: 2
    )

    static let offline = FaceAssetVariant(
        id: "offline",
        expression: .offline,
        assetName: FaceAssetCatalog.offline,
        minimumDwell: 3.2,
        transition: .crossfade(seconds: 0.28),
        allowsMicroMotion: false,
        priority: 1
    )

    static let blink = FaceAssetVariant(
        id: "blink",
        expression: .idle,
        assetName: FaceAssetCatalog.blink,
        minimumDwell: 0.12,
        transition: .immediate,
        allowsMicroMotion: false,
        priority: 1
    )
}
```

- [ ] **Step 3: Build**

Run:

```bash
xcodebuild build -project ulooi.xcodeproj -scheme ulooi -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -quiet
```

Expected: build succeeds.

- [ ] **Step 4: Commit**

```bash
git add ulooi/Main/Face/Engine/FaceRandomSource.swift ulooi/Main/Face/Engine/FaceAnimationSelector.swift
git commit -m "feat(face): select image face variants"
```

---

### Task 4: Add Image Renderer and Stage Wrapper

**Files:**
- Create: `ulooi/Main/Face/Views/ImageFaceRenderer.swift`
- Create: `ulooi/Main/Face/Views/FaceStageView.swift`

- [ ] **Step 1: Create `ImageFaceRenderer`**

Create `ulooi/Main/Face/Views/ImageFaceRenderer.swift`:

```swift
import SwiftUI

struct ImageFaceRenderer: View {
    let variant: FaceAssetVariant
    let model: FaceModel
    let phase: TimeInterval

    var body: some View {
        let breath = (sin(phase * 1.35) + 1) / 2
        let microScale = variant.allowsMicroMotion ? 1.0 + breath * 0.012 : 1.0
        let microYOffset = variant.allowsMicroMotion ? CGFloat(breath * -2.0) : 0

        ZStack {
            Color.black

            Image(variant.assetName)
                .resizable()
                .scaledToFit()
                .scaleEffect(microScale)
                .offset(y: microYOffset)
                .brightness(variant.allowsMicroMotion ? breath * 0.025 : 0)
                .accessibilityHidden(true)
        }
        .animation(animation(for: variant.transition), value: variant.id)
    }

    private func animation(for transition: FaceAssetVariant.Transition) -> Animation? {
        switch transition {
        case .immediate:
            return nil
        case .crossfade(let seconds):
            return .easeInOut(duration: seconds)
        }
    }
}
```

- [ ] **Step 2: Create `FaceStageView`**

Create `ulooi/Main/Face/Views/FaceStageView.swift`:

```swift
import SwiftUI

struct FaceStageView: View {
    let model: FaceModel
    var renderMode: FaceRenderMode = .imageAssets

    @State private var selector = FaceAnimationSelector(random: SystemFaceRandomSource())
    @State private var selectedVariant = FaceAssetVariant.idle

    var body: some View {
        TimelineView(.animation) { timeline in
            let now = timeline.date
            let phase = now.timeIntervalSinceReferenceDate

            Group {
                switch renderMode {
                case .imageAssets:
                    ImageFaceRenderer(variant: selectedVariant, model: model, phase: phase)
                case .geometricFallback:
                    GeometricFaceView(model: model)
                }
            }
            .task(id: model.expression) {
                selectedVariant = selector.selectVariant(for: model, now: now)
            }
            .onChange(of: Int(phase * 2)) {
                selectedVariant = selector.selectVariant(for: model, now: now)
            }
        }
        .background(Color.black)
    }
}
```

- [ ] **Step 3: Build and fix SwiftUI state warnings if needed**

Run:

```bash
xcodebuild build -project ulooi.xcodeproj -scheme ulooi -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -quiet
```

Expected: build succeeds. If SwiftUI complains about mutating selector state from the timeline closure, move selection into an `@Observable` `FaceAnimationDriver` in `ulooi/Main/Face/Engine/FaceAnimationDriver.swift`.

- [ ] **Step 4: Commit**

```bash
git add ulooi/Main/Face/Views/ImageFaceRenderer.swift ulooi/Main/Face/Views/FaceStageView.swift
git commit -m "feat(face): render image-based face stage"
```

---

### Task 5: Route Production Face Mode to Image Stage

**Files:**
- Modify: `ulooi/Main/EmbodiedHomeView.swift`
- Modify: `docs/m1-2-presence-smoke-test-checklist.md`

- [ ] **Step 1: Replace direct geometric renderer usage**

In `EmbodiedHomeView`, replace:

```swift
GeometricFaceView(model: face)
    .ignoresSafeArea()
```

with:

```swift
FaceStageView(model: face)
    .ignoresSafeArea()
```

- [ ] **Step 2: Add smoke checklist items**

Append to `docs/m1-2-presence-smoke-test-checklist.md`:

```markdown
## M1.5 Minimal OLED Face Visual QA

- [ ] Connected landscape Face mode uses image-generated Minimal OLED Eyes, not the geometric Canvas renderer.
- [ ] Background is pure black with no outer oval, border, robot shell, or white sheet.
- [ ] Idle face shows only simple cyan eyes with generous safe-area margins.
- [ ] Touch/gesture response can switch to happy/surprised visual without layout jump.
- [ ] Sleep state dims to sleepy face.
- [ ] Suspended/safety state uses cautious face and does not add playful random animation.
- [ ] Disconnected/phone mode remains readable and does not imply the robot body is nearby.
```

- [ ] **Step 3: Build**

Run:

```bash
xcodebuild build -project ulooi.xcodeproj -scheme ulooi -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -quiet
```

Expected: build succeeds.

- [ ] **Step 4: Commit**

```bash
git add ulooi/Main/EmbodiedHomeView.swift docs/m1-2-presence-smoke-test-checklist.md
git commit -m "feat(face): use image assets in face mode"
```

---

### Task 6: Final Visual Verification

**Files:**
- Modify only if verification finds defects.

- [ ] **Step 1: Build app**

Run:

```bash
xcodebuild build -project ulooi.xcodeproj -scheme ulooi -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -quiet
```

Expected: build succeeds.

- [ ] **Step 2: Run LooiKit regression tests**

Run:

```bash
swift test --package-path Packages/LooiKit
```

Expected: all tests pass.

- [ ] **Step 3: Real-device smoke**

Install/run on iPhone and verify:

- Connected + landscape opens Face mode.
- Face mode displays the image-generated eyes.
- Face content is not clipped by rounded corners or Dynamic Island.
- Face controls do not cover the eyes.
- Touch, wave, sleep, suspended, and disconnected states use plausible assets.

- [ ] **Step 4: Commit any visual fixes**

If fixes are needed:

```bash
git add <changed-files>
git commit -m "fix(face): polish minimal OLED face mode"
```

If no fixes are needed, do not create an empty commit.

---

## Self-Review

- **Spec coverage:** This plan implements the approved image-generated asset-first direction, preserves `FaceModel` semantic mapping, keeps `GeometricFaceView` as fallback only, and adds runtime visual QA.
- **Architecture:** Files are split by model, engine, assets, and views. No god file is introduced.
- **Testing reality:** The current Xcode project has no app test target, so this first plan relies on build verification plus LooiKit regression tests. Selector unit tests should be added once an app test target or extracted Face package exists.
- **Risk:** Generated assets may not be consistent enough across all states. The first runtime slice intentionally bundles only six assets and keeps state mapping conservative.
- **Next action:** Execute Task 1 first, then build after every task before committing.
