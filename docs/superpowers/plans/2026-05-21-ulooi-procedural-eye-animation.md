# Plan: ulooi Procedural High-Fidelity Eye Animation

To address user feedback regarding flat static images with background artifacts, this plan implements a pure procedural, multi-layered interactive eye rendering engine inside `GeometricFaceView.swift`’s SwiftUI `Canvas`. By rendering each component (Base Sclera, Glowing Iris, Pupil, Shimmering Textures, Specular Highlights, and Eyelid Curves) on its own mathematical vector layer, we achieve premium visual fidelity with zero background artifacts, fluid multi-layer 3D parallax, organic pupil dilation, breathing-driven iris shimmer, and genuine 8-bit retro pixel grid displays.

---

## ADR §18 Strategic Spec Answers

1. **Intent**: To upgrade the robot's face switching from flat, non-interactive static images with black backgrounds to an ultra-premium, interactive, and organic procedural multi-layer rendering system.
2. **Autonomy**: It runs entirely inside the local iOS client’s SwiftUI rendering loop, with no network or server dependency.
3. **Truth Source**: Driven by the AppStorage `"ulooi_face_theme"` setting and Looi's semantic `FaceModel` expression and gaze.
4. **TaskEvent**: None. This is a client-side visual layer.
5. **Context**: Integrates with SwiftUI Canvas and Looi's physical presence state-machine.
6. **Capability**: Creates an exquisite, cinema-grade visual identity with five distinct interactive themes (Disney 3D, Ghibli Watercolor, Cyberpunk Matrix, Holographic Aurora, and Minimalist Iron).
7. **Hooks**: Pre-commit hooks will check the integrity of our Swift code.
8. **Projection**: Maps Looi's `FaceExpression` and `FaceGaze` to specific procedural coordinate scaling, tilt angles, and pupil dilations.
9. **Harness**: Verified by building the iOS app and running visual QA on the Simulator or real device.
10. **Rollback**: Standard git-reset allows rolling back to the previous version instantly.
11. **What this does not own**: Does not own physical robot motors, speech synthesis, or Bluetooth pairing state.

---

## Proposed Changes

### 1. Disney 3D Cinematic Lens (`.classicWallE`)
*   **The Look**: Deep, metallic camera lens with multiple radial gradients and glossy glass reflections.
*   **Real-time Animation**:
    *   **Breathing Iris Fibers**: 24 radial rays extend from the pupil. The opacity of these lines gently oscillates and ripples with Looi's breathing, making the lens look like it is dynamically catching light!
    *   **3D Dome Parallax**: The specular glass highlight is elevated, drifting in the opposite direction of Looi's gaze to simulate the curvature of a physical glass lens dome.
    *   **Pupil Dilation**: Pupil size dynamically scales depending on expression (large and wide on `.surprised`, medium on `.idle`, narrow on `.sleepy`).

### 2. Studio Ghibli Hand-Painted Watercolor (`.nebulaCosmic`)
*   **The Look**: Cozy, soft, organic watercolor textures with slightly hand-carved, imperfect outlines (by perturbing bezier control points).
*   **Real-time Animation**:
    *   **Drifting Nebula Stardust**: Inside each eye, 6 tiny stardust particles (white and soft yellow soft-glowing dots) float slowly upward and fade in/out using a time-based phase wave.
    *   **Warm Core Glow**: A soft warm-yellow halo surrounding the pupil expands and contracts as if the eye has a firefly inside.

### 3. Retro 8-Bit Pixel Art (`.cyberpunkMatrix`)
*   **The Look**: Genuine, nostalgic retro-arcade LED matrix.
*   **Real-time Animation**:
    *   **Pixel-Grid Shader**: The bounding box is subdivided into a 12x12 grid of blocks. Cells are drawn as individual rounded squares with sub-pixel black gaps.
    *   **True Grid Shifting**: When Looi looks around, the "pupil blocks" turn on and off across the grid. When blinking, the rows of pixels turn off row-by-row.
    *   **Digital Glitch Jitter**: When Looi changes expressions (e.g. surprises), the eye has a high-frequency horizontal micro-jitter for 0.15 seconds to simulate a screen glitch!

### 4. Holographic Aurora (`.holographicAurora`)
*   **The Look**: Iridescent, neon-colored shifting space waves with concentric futuristic hologram rings.
*   **Real-time Animation**:
    *   **Flowing Aurora**: A linear gradient of electric magenta, royal purple, and cyan waves continuously flows and waves inside the eye based on time.
    *   **Expanding Aura Sonar**: 3 thin holographic concentric circles pulse outward like radar rings.

---

## File Changes

### [MODIFY] [GeometricFaceView.swift](file:///Users/ryanliu/Documents/uclaw/ulooi/ulooi/Main/Face/GeometricFaceView.swift)
- Remove static image loading and drawing.
- Add multi-layered procedural rendering inside `drawEye`.
- Add stardust particle simulation, shimmering radial fibers, and the real-time pixel grid subdivision algorithm.

### [MODIFY] [FaceModel.swift](file:///Users/ryanliu/Documents/uclaw/ulooi/ulooi/Main/Presence/FaceModel.swift)
- Polish the theme descriptions and coordinates.

---

## Verification Plan

### Automated Compilation
```bash
xcodebuild -project ulooi.xcodeproj -scheme ulooi -configuration Debug -destination 'generic/platform=iOS Simulator'
```

### Manual Verification
Visual QA of each theme's animation smoothness, 3D parallax, transparency, and expression dynamics inside the settings panel.
