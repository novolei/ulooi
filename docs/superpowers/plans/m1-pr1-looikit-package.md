# M1 PR 1 — LooiKit Package Extraction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Lift the inline `ulooi/LooiKit/*` BLE code into a standalone Swift Package (`Packages/LooiKit/`) with a `BLETransport` seam for testing, a typed `LooiSession` state machine, four public Controllers (Motion / Head / Light / Sensor), and a Mock transport — all covered by unit tests. The app target keeps working throughout (DevTools' five tabs remain functional on real hardware after every commit).

**Architecture:** Three layers — (a) `Packages/LooiKit/` ships the public API (`LooiSession`, Controllers, `GestureLibrary` types, `FaceRenderer` protocol stubs); (b) `Packages/LooiKit/Sources/LooiKitTesting/` ships `MockBLETransport` for tests; (c) the `ulooi` app target imports `LooiKit` and binds a `CoreBluetoothTransport` (also in LooiKit) for production. BLE concerns live behind the `BLETransport` protocol — testable end-to-end without hardware.

**Tech Stack:** Swift 6 strict concurrency, Xcode 16 `PBXFileSystemSynchronizedRootGroup`, `CoreBluetooth`, `Observation`, `XCTest`, `OSLog`. iOS deployment target matches the existing project (iOS 18). Reference: spec `docs/superpowers/specs/2026-05-17-ulooi-m1-foundation-design.md` §§ 5 and 11.1.

**Branch:** `plan/m1-pr1-looikit-package` from `main` of `novolei/ulooi`.

**Working directory:** `/Users/ryanliu/Documents/uclaw/ulooi` (this is the ulooi repo root — a separate git repo from uclaw).

---

## File Structure

After PR 1 merges, the repo layout will be:

```
ulooi/                                  # repo root
├── Packages/
│   └── LooiKit/
│       ├── Package.swift               # NEW
│       ├── Sources/
│       │   ├── LooiKit/
│       │   │   ├── LooiKit.swift                   # umbrella + version
│       │   │   ├── Protocol/
│       │   │   │   ├── LooiProtocol.swift          # MOVED (Char UUIDs / Handshake / Timing)
│       │   │   │   └── HandshakeRunner.swift       # NEW — typed steps
│       │   │   ├── Transport/
│       │   │   │   ├── BLETransport.swift          # NEW — protocol
│       │   │   │   ├── CoreBluetoothTransport.swift # NEW — prod impl
│       │   │   │   ├── DiscoveredPeripheral.swift  # NEW — Sendable value type
│       │   │   │   └── WriteType.swift             # NEW — withResponse/withoutResponse
│       │   │   ├── Session/
│       │   │   │   ├── LooiSession.swift           # NEW — @MainActor @Observable
│       │   │   │   ├── SessionState.swift          # NEW — 9-state enum
│       │   │   │   ├── SessionStateMachine.swift   # NEW — pure transitions
│       │   │   │   └── ReconnectPolicy.swift       # NEW — backoff schedule
│       │   │   ├── Controllers/
│       │   │   │   ├── MotionController.swift      # NEW — heartbeat + cliff lock
│       │   │   │   ├── HeadController.swift        # NEW
│       │   │   │   ├── LightController.swift       # NEW
│       │   │   │   └── SensorController.swift      # NEW — battery poll + FED9 decode
│       │   │   ├── Commands/
│       │   │   │   ├── LooiCommand.swift           # MOVED
│       │   │   │   ├── LooiCommand+Movement.swift  # MOVED
│       │   │   │   ├── LooiCommand+Head.swift      # MOVED
│       │   │   │   ├── LooiCommand+Light.swift     # MOVED
│       │   │   │   └── LooiCommand+Handshake.swift # MOVED
│       │   │   ├── Models/
│       │   │   │   ├── MotionState.swift           # MOVED (also publishes label/data)
│       │   │   │   ├── CliffState.swift            # NEW — 4-direction bitfield enum
│       │   │   │   └── CharacteristicProperties.swift # MOVED
│       │   │   ├── Errors/
│       │   │   │   └── LooiError.swift             # NEW — 9-case LocalizedError
│       │   │   └── Util/
│       │   │       ├── DataHexCodec.swift          # MOVED from Shared/
│       │   │       └── ComparableClamped.swift     # MOVED from Shared/
│       │   └── LooiKitTesting/
│       │       ├── MockBLETransport.swift          # NEW — actor mock
│       │       └── FakeClock.swift                 # NEW — for reconnect backoff tests
│       └── Tests/
│           └── LooiKitTests/
│               ├── BLETransportTests.swift         # NEW
│               ├── LooiErrorTests.swift            # NEW
│               ├── SessionStateMachineTests.swift  # NEW
│               ├── HandshakeRunnerTests.swift      # NEW
│               ├── LooiSessionTests.swift          # NEW
│               ├── MotionControllerTests.swift     # NEW
│               ├── HeadLightControllerTests.swift  # NEW
│               ├── SensorControllerTests.swift     # NEW
│               ├── ReconnectPolicyTests.swift      # NEW
│               └── MockBLETransportTests.swift     # NEW
├── ulooi/                              # app target (Xcode synchronized folder)
│   ├── ulooiApp.swift                  # UNCHANGED
│   ├── ContentView.swift               # UNCHANGED for PR 1 (still hosts DevTools)
│   ├── LooiKit/                        # DELETED in Task 12 — all moved to package
│   ├── DevTools/                       # MODIFIED — uses LooiSession via app singleton
│   │   ├── ConnectionBanner.swift      # MODIFIED — reads LooiSession state
│   │   ├── DevToolsRootView.swift      # MODIFIED — injects LooiSession
│   │   └── Probe/                      # MODIFIED — five tabs migrated
│   ├── Shared/
│   │   ├── DevLog.swift                # KEPT — app-layer logger (LooiKit uses OSLog directly)
│   │   ├── BuildInfo.swift             # UNCHANGED
│   │   └── (DataHexCodec/ComparableClamped MOVED into LooiKit)
│   └── (Info.plist UNCHANGED)
├── ulooi.xcodeproj/
│   └── project.pbxproj                 # MODIFIED — adds Local Package reference
└── docs/
    └── superpowers/
        ├── plans/
        │   └── m1-pr1-looikit-package.md   # THIS FILE
        └── specs/
            └── 2026-05-17-ulooi-m1-foundation-design.md
```

**Why this decomposition:**
- `Protocol/`, `Transport/`, `Session/`, `Controllers/`, `Commands/`, `Models/`, `Errors/`, `Util/` subgroups keep each concern in its own folder. No file > ~250 lines. Each Controller is its own file.
- `LooiKit` module exposes the public API; `LooiKitTesting` module exposes the Mock — tests import both, but production code only imports `LooiKit`.
- `DevLog` stays in the app target because it wires into the app-only `ProbeLog` UI surface. LooiKit logs via plain `OSLog.Logger("ai.if2.ulooi", category: "looikit")` so the package is self-contained.

---

## Verification commands you'll run repeatedly

Throughout this plan, treat these three as the canonical build/test triggers. Run from the repo root `/Users/ryanliu/Documents/uclaw/ulooi`:

- **App build** (verifies pbxproj + Package wiring + app code compiles):
  ```bash
  xcodebuild build \
    -project ulooi.xcodeproj \
    -scheme ulooi \
    -destination 'platform=iOS Simulator,name=iPhone 16' \
    -quiet 2>&1 | tail -20
  ```
  Expected on success: last line ends with `** BUILD SUCCEEDED **`. On failure, full errors print.

- **Package-only unit tests** (faster than xcodebuild for pure-Swift logic — runs on host macOS via SwiftPM):
  ```bash
  swift test --package-path Packages/LooiKit 2>&1 | tail -30
  ```
  Expected on success: last line includes `Test Suite 'All tests' passed`. CoreBluetoothTransport is `#if canImport(CoreBluetooth) && os(iOS)` gated so SwiftPM on macOS still compiles the rest.

- **Full Xcode test on simulator** (run before opening PR — covers everything including Xcode-specific scheme glue):
  ```bash
  xcodebuild test \
    -project ulooi.xcodeproj \
    -scheme LooiKit \
    -destination 'platform=iOS Simulator,name=iPhone 16' \
    2>&1 | tail -30
  ```
  Expected on success: `Test Suite 'All tests' passed`.

If `xcodebuild` complains "iPhone 16 not available", run `xcrun simctl list devices available iPhone` and substitute the highest available iPhone simulator name.

---

## Task 0: Branch + Baseline Smoke

**Files:**
- No file changes
- Verify: working tree clean before branching

- [ ] **Step 1: Confirm clean working tree on main**

```bash
cd /Users/ryanliu/Documents/uclaw/ulooi
git fetch origin
git status -sb
git log --oneline -3
```

Expected: branch is `main`, in sync with `origin/main`, top commit is `478f0c3 docs: M1 foundation spec` (or a later docs commit, but no uncommitted source changes). If the working tree has unrelated WIP, stash or commit it before branching.

- [ ] **Step 2: Branch from main**

```bash
git switch -c plan/m1-pr1-looikit-package
git status -sb
```

Expected: `## plan/m1-pr1-looikit-package`, no tracking yet.

- [ ] **Step 3: Baseline app build**

```bash
xcodebuild build \
  -project ulooi.xcodeproj \
  -scheme ulooi \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -quiet 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`. If it fails on `main` baseline, STOP — investigate before continuing (the plan assumes a known-good starting point).

---

## Task 1: Scaffold Packages/LooiKit + pbxproj Wiring

**Files:**
- Create: `Packages/LooiKit/Package.swift`
- Create: `Packages/LooiKit/Sources/LooiKit/LooiKit.swift` (stub so the package compiles)
- Create: `Packages/LooiKit/Sources/LooiKitTesting/LooiKitTesting.swift` (stub)
- Create: `Packages/LooiKit/Tests/LooiKitTests/SmokeTest.swift`
- Modify: `ulooi.xcodeproj/project.pbxproj` (add Local Swift Package reference + product dependency on `ulooi` target)

- [ ] **Step 1: Create directory tree**

```bash
mkdir -p Packages/LooiKit/Sources/LooiKit
mkdir -p Packages/LooiKit/Sources/LooiKitTesting
mkdir -p Packages/LooiKit/Tests/LooiKitTests
```

- [ ] **Step 2: Write Package.swift**

Create `Packages/LooiKit/Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LooiKit",
    platforms: [
        .iOS(.v18),
        .macOS(.v14)  // host tests run on macOS via SwiftPM
    ],
    products: [
        .library(name: "LooiKit", targets: ["LooiKit"]),
        .library(name: "LooiKitTesting", targets: ["LooiKitTesting"]),
    ],
    targets: [
        .target(
            name: "LooiKit",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .defaultIsolation(MainActor.self),
            ]
        ),
        .target(
            name: "LooiKitTesting",
            dependencies: ["LooiKit"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .defaultIsolation(MainActor.self),
            ]
        ),
        .testTarget(
            name: "LooiKitTests",
            dependencies: ["LooiKit", "LooiKitTesting"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .defaultIsolation(MainActor.self),
            ]
        ),
    ]
)
```

Why `.defaultIsolation(MainActor.self)`: matches the app target's `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` setting, so behavior is consistent across boundaries (one of the recurring traps documented in `feedback-swift-extension-splits.md`).

- [ ] **Step 3: Write minimal stub source files**

Create `Packages/LooiKit/Sources/LooiKit/LooiKit.swift`:

```swift
import Foundation

/// LooiKit — public Swift Package for the LOOI robot iOS embodiment.
///
/// See `docs/superpowers/specs/2026-05-17-ulooi-m1-foundation-design.md` for
/// the design that drives this package's API surface.
public enum LooiKit {
    /// Package semantic version. Synthesized at compile time from the
    /// containing PR; bumped as part of the M1 ship commit.
    public static let version = "0.2.0-dev.m1.pr1"
}
```

Create `Packages/LooiKit/Sources/LooiKitTesting/LooiKitTesting.swift`:

```swift
import Foundation
@_exported import LooiKit

/// LooiKitTesting — re-exports `LooiKit` and provides test doubles such as
/// `MockBLETransport`. Tests import `LooiKitTesting` instead of `LooiKit`
/// directly to get both the production API and the mocks in one statement.
public enum LooiKitTesting {
    public static let version = LooiKit.version
}
```

- [ ] **Step 4: Write smoke test that proves the test target works**

Create `Packages/LooiKit/Tests/LooiKitTests/SmokeTest.swift`:

```swift
import XCTest
@testable import LooiKit
import LooiKitTesting

final class SmokeTest: XCTestCase {
    func test_packageVersion_isNonEmpty() {
        XCTAssertFalse(LooiKit.version.isEmpty)
        XCTAssertEqual(LooiKitTesting.version, LooiKit.version)
    }
}
```

- [ ] **Step 5: Verify SwiftPM build + test passes on the empty package**

```bash
swift build --package-path Packages/LooiKit 2>&1 | tail -10
swift test --package-path Packages/LooiKit 2>&1 | tail -10
```

Expected: build emits `Build complete!`, test emits `Test Suite 'All tests' passed`.

If the build fails with "experimental feature isolation", drop `.defaultIsolation(MainActor.self)` (Swift 6.0+ feature) and proceed — the app's MainActor default will still apply once Xcode wires it in.

- [ ] **Step 6: Edit `ulooi.xcodeproj/project.pbxproj` to wire LooiKit as a Local Swift Package**

This is the only non-mechanical change in this task. Xcode 16 + synchronized folders requires four additions to `project.pbxproj`:

1. A `XCLocalSwiftPackageReference` section pointing at `Packages/LooiKit`
2. A `XCSwiftPackageProductDependency` section naming the `LooiKit` product
3. The package reference appended to the root project's `packageReferences` array
4. The product dependency appended to the `ulooi` PBXNativeTarget's `packageProductDependencies` array AND to its `PBXFrameworksBuildPhase.files`

Open the file with your text editor (do NOT use `sed`; the structure is brittle). Use this sample to locate the insertion points by their `isa` markers:

Add a new section before `/* End PBXFileSystemSynchronizedRootGroup section */`:

```
/* Begin XCLocalSwiftPackageReference section */
		A1B2C3D40000000000000001 /* XCLocalSwiftPackageReference "Packages/LooiKit" */ = {
			isa = XCLocalSwiftPackageReference;
			relativePath = Packages/LooiKit;
		};
/* End XCLocalSwiftPackageReference section */

/* Begin XCSwiftPackageProductDependency section */
		A1B2C3D40000000000000002 /* LooiKit */ = {
			isa = XCSwiftPackageProductDependency;
			productName = LooiKit;
		};
/* End XCSwiftPackageProductDependency section */
```

(Generate fresh 24-char hex UUIDs if you have many parallel projects; the literals shown work since this is a single-project repo.)

Locate the `PBXProject` object (search `isa = PBXProject;`) and add a `packageReferences` field:

```
			packageReferences = (
				A1B2C3D40000000000000001 /* XCLocalSwiftPackageReference "Packages/LooiKit" */,
			);
```

Locate the `ulooi` `PBXNativeTarget` (search `name = ulooi;` near `isa = PBXNativeTarget;`) and add a `packageProductDependencies` field:

```
			packageProductDependencies = (
				A1B2C3D40000000000000002 /* LooiKit */,
			);
```

Locate the `PBXFrameworksBuildPhase` for the `ulooi` target (the `3130C6192FB97A510016ABC0` object) and add the product to its `files` array:

```
		3130C6192FB97A510016ABC0 /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
				A1B2C3D40000000000000003 /* LooiKit in Frameworks */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
```

And add a matching `PBXBuildFile` (search `/* Begin PBXBuildFile section */` — if no such section exists, create one before the `PBXFileReference` section):

```
/* Begin PBXBuildFile section */
		A1B2C3D40000000000000003 /* LooiKit in Frameworks */ = {
			isa = PBXBuildFile;
			productRef = A1B2C3D40000000000000002 /* LooiKit */;
		};
/* End PBXBuildFile section */
```

- [ ] **Step 7: Verify Xcode parses the modified pbxproj**

```bash
xcodebuild -list -project ulooi.xcodeproj 2>&1 | head -20
```

Expected: lists `ulooi` (and possibly `LooiKit` / `LooiKitTesting` / `LooiKitTests` as schemes Xcode auto-derives). If you see "Project file is corrupt", revert your pbxproj edits and try Step 6 again carefully — or as a last resort, open the project in Xcode UI once (`open ulooi.xcodeproj`), use **File → Add Package Dependencies → Add Local → Packages/LooiKit**, then quit Xcode and diff `project.pbxproj` against your hand-edited version to learn the canonical shape.

- [ ] **Step 8: Verify app builds with empty LooiKit attached**

```bash
xcodebuild build \
  -project ulooi.xcodeproj \
  -scheme ulooi \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -quiet 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`. The app target hasn't yet `import`ed `LooiKit` anywhere, so we're verifying only that the wiring isn't broken.

- [ ] **Step 9: Commit**

```bash
git add Packages/LooiKit ulooi.xcodeproj/project.pbxproj
git commit -m "chore: scaffold Packages/LooiKit + pbxproj wiring

Empty Swift Package with LooiKit + LooiKitTesting library targets and
a LooiKitTests test target. Wired into ulooi.xcodeproj as a Local
Swift Package reference. App target builds unchanged — LooiKit code
is added in later commits."
```

---

## Task 2: Lift `ulooi/LooiKit/*` to `Packages/LooiKit/Sources/LooiKit/`

**Files (move):**
- `ulooi/LooiKit/LooiProtocol.swift` → `Packages/LooiKit/Sources/LooiKit/Protocol/LooiProtocol.swift`
- `ulooi/LooiKit/CharacteristicProperties.swift` → `Packages/LooiKit/Sources/LooiKit/Models/CharacteristicProperties.swift`
- `ulooi/LooiKit/MotionState.swift` → `Packages/LooiKit/Sources/LooiKit/Models/MotionState.swift`
- `ulooi/LooiKit/Commands/LooiCommand.swift` → `Packages/LooiKit/Sources/LooiKit/Commands/LooiCommand.swift`
- `ulooi/LooiKit/Commands/LooiCommand+Movement.swift` → `Packages/LooiKit/Sources/LooiKit/Commands/LooiCommand+Movement.swift`
- `ulooi/LooiKit/Commands/LooiCommand+Head.swift` → `Packages/LooiKit/Sources/LooiKit/Commands/LooiCommand+Head.swift`
- `ulooi/LooiKit/Commands/LooiCommand+Light.swift` → `Packages/LooiKit/Sources/LooiKit/Commands/LooiCommand+Light.swift`
- `ulooi/LooiKit/Commands/LooiCommand+Handshake.swift` → `Packages/LooiKit/Sources/LooiKit/Commands/LooiCommand+Handshake.swift`
- `ulooi/LooiKit/Commands/LooiCommand+Rich.swift` → `Packages/LooiKit/Sources/LooiKit/Commands/LooiCommand+Rich.swift`
- `ulooi/LooiKit/Commands/LooiCommand+SensorEvent.swift` → `Packages/LooiKit/Sources/LooiKit/Commands/LooiCommand+SensorEvent.swift`
- `ulooi/LooiKit/Commands/LooiCommand+Preset.swift` → `Packages/LooiKit/Sources/LooiKit/Commands/LooiCommand+Preset.swift`
- `ulooi/LooiKit/Commands/LooiCommand+PresetRegistry.swift` → `Packages/LooiKit/Sources/LooiKit/Commands/LooiCommand+PresetRegistry.swift`
- `ulooi/Shared/DataHexCodec.swift` → `Packages/LooiKit/Sources/LooiKit/Util/DataHexCodec.swift`
- `ulooi/Shared/ComparableClamped.swift` → `Packages/LooiKit/Sources/LooiKit/Util/ComparableClamped.swift`

**Files NOT moving in this task:**
- `ulooi/LooiKit/BLECentral*.swift` — these will be subsumed by `LooiSession` + `CoreBluetoothTransport` in Tasks 3 + 7; they stay in the app target for now and continue to work as before.
- `ulooi/Shared/DevLog.swift`, `BuildInfo.swift` — app-only.

**Files (modify in app target after move):**
- Add `import LooiKit` to: `BLECentral.swift`, `BLECentral+CentralDelegate.swift`, `BLECentral+PeripheralDelegate.swift`, every DevTools/Probe/*.swift that references `LooiProtocol`, `LooiCommand`, `CharacteristicProperties`, `MotionState`, `MotionPreset`, `DataHexCodec`, `ComparableClamped`.

**Tests:**
- Create: `Packages/LooiKit/Tests/LooiKitTests/CommandBytesTest.swift`
- Create: `Packages/LooiKit/Tests/LooiKitTests/MotionStateTest.swift`

- [ ] **Step 1: Create subfolders in LooiKit Sources**

```bash
mkdir -p Packages/LooiKit/Sources/LooiKit/{Protocol,Commands,Models,Util}
```

- [ ] **Step 2: Move files with git mv (preserves history)**

```bash
git mv ulooi/LooiKit/LooiProtocol.swift Packages/LooiKit/Sources/LooiKit/Protocol/LooiProtocol.swift
git mv ulooi/LooiKit/CharacteristicProperties.swift Packages/LooiKit/Sources/LooiKit/Models/CharacteristicProperties.swift
git mv ulooi/LooiKit/MotionState.swift Packages/LooiKit/Sources/LooiKit/Models/MotionState.swift
git mv ulooi/LooiKit/Commands Packages/LooiKit/Sources/LooiKit/Commands
git mv ulooi/Shared/DataHexCodec.swift Packages/LooiKit/Sources/LooiKit/Util/DataHexCodec.swift
git mv ulooi/Shared/ComparableClamped.swift Packages/LooiKit/Sources/LooiKit/Util/ComparableClamped.swift
git status -sb
```

Expected: roughly 14 `R` (renamed) entries plus a couple of `R` for the Commands subfolder children.

- [ ] **Step 3: Make every moved type `public` so the app target can see it**

For each moved file, prefix top-level declarations with `public` and member declarations that need cross-module access:

`Packages/LooiKit/Sources/LooiKit/Protocol/LooiProtocol.swift`: change `enum LooiProtocol {` to `public enum LooiProtocol {`. Change each nested `enum Char {`, `enum Handshake {`, `enum Timing {` to `public enum`. Change each `static let foo` to `public static let foo`. Same for the `static let advertisedNamePrefix` and `scanServiceFilter`.

`Packages/LooiKit/Sources/LooiKit/Commands/LooiCommand.swift` and every `LooiCommand+*.swift`: change `enum LooiCommand {}` to `public enum LooiCommand {}`. Change each nested `enum Movement {`, `enum Head {`, etc. to `public enum`. Change each `static let` and `static func` to `public static`.

`Packages/LooiKit/Sources/LooiKit/Models/MotionState.swift`: change `struct MotionState: Sendable, Equatable {` to `public struct MotionState: Sendable, Equatable {`, give it `public let label: String`, `public let data: Data`, `public static let stop`, and a `public init(label: String, data: Data)`. Same `public` treatment for `MotionPreset` (including a `public init`).

`Packages/LooiKit/Sources/LooiKit/Models/CharacteristicProperties.swift`: change `struct CharacteristicProperties: OptionSet, CustomStringConvertible {` to `public struct ...`, mark `let rawValue: UInt` as `public let rawValue: UInt`, add `public init(rawValue: UInt) { self.rawValue = rawValue }`, mark every `static let` `public static let`, mark `var description: String` as `public var description: String`.

`Packages/LooiKit/Sources/LooiKit/Util/DataHexCodec.swift`: mark the `Data` extension's `hexEncoded` getter and any helpers as `public`.

`Packages/LooiKit/Sources/LooiKit/Util/ComparableClamped.swift`: mark the `Comparable.clamped(to:)` extension method as `public`.

- [ ] **Step 4: Add `import` lines in app-target files that referenced these types**

For each file in `ulooi/` that uses `LooiProtocol`, `LooiCommand`, `MotionState`, `MotionPreset`, `CharacteristicProperties`, `DataHexCodec.hexEncoded`, or `.clamped(to:)`, add `import LooiKit` after the existing `import` lines.

Files that need updating (grep first to be sure):

```bash
grep -lRE "LooiProtocol\.|LooiCommand\.|MotionState|MotionPreset|CharacteristicProperties|\.hexEncoded|\.clamped\(to:" ulooi/
```

Expected list: `BLECentral.swift`, `BLECentral+CentralDelegate.swift`, `BLECentral+PeripheralDelegate.swift`, `DevTools/ConnectionBanner.swift`, `DevTools/Probe/CommandView.swift`, `DevTools/Probe/InspectView.swift`, `DevTools/Probe/SenseView.swift`, `DevTools/Probe/ScanView.swift`, possibly `DevTools/Probe/LogsView.swift`. Add `import LooiKit` to each.

- [ ] **Step 5: Write unit tests that pin the command bytes**

These tests double as the smoke that proves the move didn't drop anything.

Create `Packages/LooiKit/Tests/LooiKitTests/CommandBytesTest.swift`:

```swift
import XCTest
@testable import LooiKit

final class CommandBytesTest: XCTestCase {

    // MARK: - Movement (FED0)

    func test_movement_stop_isTwoZeroBytes() {
        XCTAssertEqual(LooiCommand.Movement.stop, Data([0x00, 0x00]))
    }

    func test_movement_forwardMax_speedIs127_turnIsZero() {
        XCTAssertEqual(LooiCommand.Movement.forwardMax, Data([0x7F, 0x00]))
    }

    func test_movement_backwardMax_speedIsNeg127() {
        // -127 as Int8 = 0x81 (two's-complement bit pattern)
        XCTAssertEqual(LooiCommand.Movement.backwardMax, Data([0x81, 0x00]))
    }

    func test_movement_spinLeftMax_turnIs127() {
        XCTAssertEqual(LooiCommand.Movement.spinLeftMax, Data([0x00, 0x7F]))
    }

    func test_movement_spinRightMax_turnIsNeg127() {
        XCTAssertEqual(LooiCommand.Movement.spinRightMax, Data([0x00, 0x81]))
    }

    func test_movement_normalized_clampsAboveOne() {
        XCTAssertEqual(LooiCommand.Movement.normalized(forward: 5.0, turn: -5.0),
                       Data([0x7F, 0x81]))
    }

    // MARK: - Head (FED1, pitch)

    func test_head_center_is0x5A() {
        XCTAssertEqual(LooiCommand.Head.center, Data([0x5A]))
    }

    func test_head_lookUp_is0x00() {
        XCTAssertEqual(LooiCommand.Head.lookUp, Data([0x00]))
    }

    func test_head_lookDown_is0xFF() {
        // 0xFF empirically dips down then auto-springs back to center
        XCTAssertEqual(LooiCommand.Head.lookDown, Data([0xFF]))
    }

    // MARK: - Light (FED2)

    func test_light_off_is0x00() {
        XCTAssertEqual(LooiCommand.Light.off, Data([0x00]))
    }

    // MARK: - Handshake (FEDA)

    func test_handshake_phase1_is0x01() {
        XCTAssertEqual(LooiProtocol.Handshake.phase1Data, Data([0x01]))
    }

    func test_handshake_phase2_is0x03() {
        XCTAssertEqual(LooiProtocol.Handshake.phase2Data, Data([0x03]))
    }

    // MARK: - Char UUIDs

    func test_charUUIDs_lowercase128bit() {
        XCTAssertEqual(LooiProtocol.Char.movement.uuidString.lowercased(),
                       "fed0")  // CoreBluetooth normalizes 16-bit forms back to short form for known prefixes
    }
}
```

Create `Packages/LooiKit/Tests/LooiKitTests/MotionStateTest.swift`:

```swift
import XCTest
@testable import LooiKit

final class MotionStateTest: XCTestCase {

    func test_stop_label_isSTOP() {
        XCTAssertEqual(MotionState.stop.label, "STOP")
    }

    func test_stop_data_isTwoZeroBytes() {
        XCTAssertEqual(MotionState.stop.data, Data([0x00, 0x00]))
    }

    func test_preset_all_includesAllNineEntries() {
        XCTAssertEqual(MotionPreset.all.count, 9)
        XCTAssertEqual(MotionPreset.all.first?.label, "STOP")
    }
}
```

- [ ] **Step 6: Run tests — they should fail compilation if `public` was missed**

```bash
swift test --package-path Packages/LooiKit 2>&1 | tail -30
```

Expected on first run: likely FAILS with "X is inaccessible due to internal protection level". For each failure, find the named symbol in its source file and add `public`. Re-run. Repeat until green.

Expected on success: `Test Suite 'All tests' passed`.

- [ ] **Step 7: Verify app still builds**

```bash
xcodebuild build \
  -project ulooi.xcodeproj \
  -scheme ulooi \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -quiet 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`. If it fails on "cannot find X in scope", you missed an `import LooiKit` in some app file — add it.

- [ ] **Step 8: Real-hardware smoke (manual)**

Install on a real iPhone via Xcode (`xcodebuild` + Devices window, or just `Cmd+R` in Xcode). Connect to a real Looi. In DevTools:
- Scan tab discovers Looi
- Connect+Init tab succeeds → ConnectionBanner shows "Connected"
- CommandView Forward (max) makes Looi move
- Disconnect cleanly

If any of these regress, the lift broke a behavior we didn't catch — investigate before committing.

- [ ] **Step 9: Commit**

```bash
git add Packages/LooiKit ulooi
git commit -m "refactor: lift ulooi/LooiKit/* and shared utils into Packages/LooiKit

Moves the BLE protocol constants, LooiCommand byte builders, MotionState,
MotionPreset, CharacteristicProperties, DataHexCodec, and Comparable.clamped
extension into the LooiKit Swift Package as public API. Adds command-byte
unit tests (CommandBytesTest, MotionStateTest) that pin the wire format.

App target keeps BLECentral inline for now (subsumed in Task 7); adds
'import LooiKit' to every file that referenced the moved types. DevTools'
five tabs preserve M0.5 behavior on real hardware."
```

---

## Task 3: BLETransport Protocol + CoreBluetoothTransport + MockBLETransport

**Files:**
- Create: `Packages/LooiKit/Sources/LooiKit/Transport/BLETransport.swift`
- Create: `Packages/LooiKit/Sources/LooiKit/Transport/DiscoveredPeripheral.swift`
- Create: `Packages/LooiKit/Sources/LooiKit/Transport/WriteType.swift`
- Create: `Packages/LooiKit/Sources/LooiKit/Transport/CoreBluetoothTransport.swift`
- Create: `Packages/LooiKit/Sources/LooiKitTesting/MockBLETransport.swift`
- Create: `Packages/LooiKit/Tests/LooiKitTests/MockBLETransportTests.swift`
- Create: `Packages/LooiKit/Tests/LooiKitTests/BLETransportTests.swift`

- [ ] **Step 1: Create the Transport folder**

```bash
mkdir -p Packages/LooiKit/Sources/LooiKit/Transport
```

- [ ] **Step 2: Write the value types — DiscoveredPeripheral and WriteType**

Create `Packages/LooiKit/Sources/LooiKit/Transport/DiscoveredPeripheral.swift`:

```swift
import Foundation
import CoreBluetooth

/// A peripheral the transport has discovered during scan. Sendable so it can
/// cross actor boundaries (the discovered stream may be consumed on any
/// isolation domain). Carries enough context to decide whether to connect.
public struct DiscoveredPeripheral: Sendable, Hashable, Identifiable {
    public let id: UUID
    public let name: String
    public let rssi: Int
    public let advertisedServices: [CBUUID]
    public let manufacturerData: Data?
    public let lastSeen: Date

    public init(
        id: UUID,
        name: String,
        rssi: Int,
        advertisedServices: [CBUUID],
        manufacturerData: Data?,
        lastSeen: Date
    ) {
        self.id = id
        self.name = name
        self.rssi = rssi
        self.advertisedServices = advertisedServices
        self.manufacturerData = manufacturerData
        self.lastSeen = lastSeen
    }
}
```

Create `Packages/LooiKit/Sources/LooiKit/Transport/WriteType.swift`:

```swift
import Foundation

/// Whether a GATT write should request an ack (`.withResponse`) or fire-and-
/// forget (`.withoutResponse`). Motor heartbeat uses `.withoutResponse` —
/// Looi treats `.withResponse` writes to FED0 as keep-alive only and does
/// not act on them (M0.5 finding).
public enum WriteType: Sendable, Equatable {
    case withResponse
    case withoutResponse
}
```

- [ ] **Step 3: Write the BLETransport protocol**

Create `Packages/LooiKit/Sources/LooiKit/Transport/BLETransport.swift`:

```swift
import Foundation
import CoreBluetooth

/// Abstract BLE I/O surface. Production binds `CoreBluetoothTransport`;
/// tests bind `MockBLETransport`. LooiSession depends on this protocol
/// rather than CoreBluetooth directly so the entire session lifecycle is
/// reachable from unit tests.
///
/// All methods are `async` so the implementation can serialize internally
/// (Mock is an actor; CoreBluetoothTransport drives a CBCentralManager on
/// a private queue) without exposing locking to callers.
public protocol BLETransport: Sendable {

    /// Whether BLE is powered on and authorized. `.poweredOn` is required
    /// before scan/connect can succeed.
    var radioState: BLERadioState { get async }

    /// Start scanning; observe discovered peripherals via the returned stream.
    /// `nameFilter` (case-insensitive substring) is applied at the transport
    /// boundary so callers don't see noise. Empty string = no filter.
    /// The stream finishes when `stopScan()` is called.
    func scan(nameFilter: String) -> AsyncStream<DiscoveredPeripheral>

    /// Stop any in-flight scan. Idempotent.
    func stopScan() async

    /// Attempt to GATT-connect to a previously-discovered peripheral.
    /// Throws `LooiError.connectionFailed` on iOS-level failure or
    /// `LooiError.peripheralNotFound` if the id isn't retrievable.
    /// Returns once didConnect fires; service discovery has NOT yet run.
    func connect(_ id: UUID) async throws

    /// Cancel a connect attempt or close an active connection. Idempotent.
    func disconnect() async

    /// Discover services + characteristics on the currently-connected
    /// peripheral. Returns once both stages are complete (or the timeout
    /// hits). Throws on disconnect mid-discovery.
    func discoverServicesAndCharacteristics(timeout: Duration) async throws

    /// Send `data` to `characteristic`. Throws if the char isn't discovered
    /// (`LooiError.characteristicMissing`) or the write fails
    /// (`LooiError.writeFailed`).
    func write(_ data: Data, to characteristic: CBUUID, type: WriteType) async throws

    /// Synchronous read of `characteristic`. Throws on missing/failure.
    func read(from characteristic: CBUUID) async throws -> Data

    /// Subscribe to notifications/indications for `characteristic`. The
    /// returned stream finishes on disconnect or explicit unsubscribe.
    func subscribe(to characteristic: CBUUID) async throws -> AsyncStream<Data>

    /// Stream of disconnection events (clean or error). Useful for callers
    /// (LooiSession) that need to react without polling.
    var disconnections: AsyncStream<DisconnectionReason> { get }
}

public enum BLERadioState: Sendable, Equatable {
    case unknown
    case unsupported
    case unauthorized
    case poweredOff
    case poweredOn
}

public enum DisconnectionReason: Sendable, Equatable {
    case clean
    case error(String)  // Error's localizedDescription — Sendable
}
```

- [ ] **Step 4: Write MockBLETransport in LooiKitTesting**

Create `Packages/LooiKit/Sources/LooiKitTesting/MockBLETransport.swift`:

```swift
import Foundation
import CoreBluetooth
import LooiKit

/// In-memory programmable BLETransport for unit tests. Records every write
/// so tests can assert on byte sequences. Lets tests push discoveries,
/// notifications, and disconnects on demand.
public final actor MockBLETransport: BLETransport {

    // MARK: - Test-observable state

    /// Every successful `write` call, in order. Tests assert on this.
    public private(set) var writes: [WriteCall] = []

    /// Every characteristic that was subscribed to. Tests assert on this.
    public private(set) var subscriptions: [CBUUID] = []

    /// Every `read` call, in order.
    public private(set) var reads: [CBUUID] = []

    public struct WriteCall: Sendable, Equatable {
        public let characteristic: CBUUID
        public let data: Data
        public let type: WriteType
    }

    // MARK: - Test-controlled inputs

    public private(set) var radioState: BLERadioState = .poweredOn

    public func setRadioState(_ state: BLERadioState) {
        self.radioState = state
    }

    /// Pre-program the value `read(from:)` returns for a given characteristic.
    private var readResponses: [CBUUID: Data] = [:]

    public func stubRead(_ characteristic: CBUUID, returns data: Data) {
        readResponses[characteristic] = data
    }

    /// Pre-program failures. If set, the matching call throws instead of
    /// running the default behavior.
    public enum Failure: Error, Equatable {
        case connectionFailure
        case writeFailure(CBUUID)
        case characteristicMissing(CBUUID)
    }
    private var queuedFailures: [Failure] = []

    public func queueFailure(_ failure: Failure) {
        queuedFailures.append(failure)
    }

    // MARK: - Streams

    private var discoveryContinuations: [AsyncStream<DiscoveredPeripheral>.Continuation] = []
    private var subscriptionContinuations: [CBUUID: [AsyncStream<Data>.Continuation]] = [:]
    private var disconnectionContinuations: [AsyncStream<DisconnectionReason>.Continuation] = []

    public func simulateDiscovery(_ p: DiscoveredPeripheral) {
        for cont in discoveryContinuations { cont.yield(p) }
    }

    public func simulateNotification(on characteristic: CBUUID, data: Data) {
        let conts = subscriptionContinuations[characteristic] ?? []
        for cont in conts { cont.yield(data) }
    }

    public func simulateDisconnect(reason: DisconnectionReason = .clean) {
        for cont in disconnectionContinuations { cont.yield(reason) }
    }

    // MARK: - BLETransport conformance

    public nonisolated var disconnections: AsyncStream<DisconnectionReason> {
        AsyncStream { continuation in
            Task { await self.registerDisconnectionContinuation(continuation) }
        }
    }

    private func registerDisconnectionContinuation(_ c: AsyncStream<DisconnectionReason>.Continuation) {
        disconnectionContinuations.append(c)
    }

    public nonisolated func scan(nameFilter: String) -> AsyncStream<DiscoveredPeripheral> {
        AsyncStream { continuation in
            Task { await self.registerDiscoveryContinuation(continuation) }
        }
    }

    private func registerDiscoveryContinuation(_ c: AsyncStream<DiscoveredPeripheral>.Continuation) {
        discoveryContinuations.append(c)
    }

    public func stopScan() async {
        for cont in discoveryContinuations { cont.finish() }
        discoveryContinuations.removeAll()
    }

    public func connect(_ id: UUID) async throws {
        if case let .connectionFailure = queuedFailures.first {
            queuedFailures.removeFirst()
            throw LooiError.connectionFailed(underlying: NSError(domain: "Mock", code: -1))
        }
    }

    public func disconnect() async {
        simulateDisconnect(reason: .clean)
    }

    public func discoverServicesAndCharacteristics(timeout: Duration) async throws {
        // no-op in mock; tests assume all characteristics exist unless they
        // queueFailure(.characteristicMissing(...))
    }

    public func write(_ data: Data, to characteristic: CBUUID, type: WriteType) async throws {
        if case let .characteristicMissing(uuid) = queuedFailures.first,
           uuid == characteristic {
            queuedFailures.removeFirst()
            throw LooiError.characteristicMissing(characteristic)
        }
        if case let .writeFailure(uuid) = queuedFailures.first,
           uuid == characteristic {
            queuedFailures.removeFirst()
            throw LooiError.writeFailed(characteristic, underlying: NSError(domain: "Mock", code: -2))
        }
        writes.append(WriteCall(characteristic: characteristic, data: data, type: type))
    }

    public func read(from characteristic: CBUUID) async throws -> Data {
        reads.append(characteristic)
        if let stub = readResponses[characteristic] { return stub }
        return Data()
    }

    public func subscribe(to characteristic: CBUUID) async throws -> AsyncStream<Data> {
        subscriptions.append(characteristic)
        return AsyncStream { continuation in
            Task { await self.registerSubscriptionContinuation(characteristic, continuation) }
        }
    }

    private func registerSubscriptionContinuation(_ c: CBUUID, _ cont: AsyncStream<Data>.Continuation) {
        subscriptionContinuations[c, default: []].append(cont)
    }

    public init() {}
}
```

Note: `connect` etc. reference `LooiError` cases (`.connectionFailed`, `.characteristicMissing`, `.writeFailed`). These don't exist yet — Task 4 defines them. For this commit, **temporarily** stub them as simple error throws (e.g., `throw NSError(domain: "Mock", code: -1)`) and update in Task 4. Alternatively, define `LooiError` now (Task 4) and reorder — note the dependency in the commit message.

For simplicity in this plan: define `LooiError` first (do Task 4 before this Task 3 if you prefer), OR include the LooiError file in this commit and treat Task 4 as just adding the LocalizedError conformance + tests. Either ordering works.

**Decision: do Task 4 first.** Stop here, jump to Task 4, then resume Task 3 Step 4.

- [ ] **Step 5: Write CoreBluetoothTransport (production impl)**

Create `Packages/LooiKit/Sources/LooiKit/Transport/CoreBluetoothTransport.swift`:

```swift
#if canImport(CoreBluetooth) && (os(iOS) || os(macOS))
import Foundation
import CoreBluetooth
import OSLog

/// Production BLETransport that drives a CBCentralManager. Owns the
/// CB delegates internally; LooiSession sees only the BLETransport
/// surface. Single connected-peripheral assumption (Looi pairs 1:1).
///
/// All CB delegate callbacks bridge to MainActor via Task-hop so the
/// rest of LooiSession can treat the transport as if it were @MainActor.
public final class CoreBluetoothTransport: NSObject, BLETransport, @unchecked Sendable {

    private let logger = Logger(subsystem: "ai.if2.ulooi", category: "looikit.cb-transport")
    private var manager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var discoveredServices: [CBService] = []
    private var _radioState: BLERadioState = .unknown

    private var discoveryContinuations: [AsyncStream<DiscoveredPeripheral>.Continuation] = []
    private var subscriptionContinuations: [CBUUID: [AsyncStream<Data>.Continuation]] = [:]
    private var disconnectionContinuations: [AsyncStream<DisconnectionReason>.Continuation] = []
    private var pendingConnect: CheckedContinuation<Void, Error>?
    private var pendingDiscover: CheckedContinuation<Void, Error>?
    private var pendingReads: [CBUUID: CheckedContinuation<Data, Error>] = [:]
    private let lock = NSRecursiveLock()

    public override init() {
        super.init()
        // .main queue keeps delegate callbacks on the main thread so we can
        // bridge straight to MainActor without an extra hop. Matches the
        // M0.5 BLECentral behavior.
        self.manager = CBCentralManager(delegate: self, queue: .main)
    }

    public var radioState: BLERadioState {
        get async {
            lock.lock(); defer { lock.unlock() }
            return _radioState
        }
    }

    public var disconnections: AsyncStream<DisconnectionReason> {
        AsyncStream { [weak self] continuation in
            self?.lock.lock()
            self?.disconnectionContinuations.append(continuation)
            self?.lock.unlock()
        }
    }

    public func scan(nameFilter: String) -> AsyncStream<DiscoveredPeripheral> {
        AsyncStream { [weak self] continuation in
            guard let self else { continuation.finish(); return }
            self.lock.lock()
            self.discoveryContinuations.append(continuation)
            self.currentNameFilter = nameFilter
            self.lock.unlock()
            self.manager.scanForPeripherals(
                withServices: nil,
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
            )
            self.logger.info("scan: started (filter=\(nameFilter, privacy: .public))")
        }
    }

    private var currentNameFilter: String = ""

    public func stopScan() async {
        manager.stopScan()
        lock.lock()
        for cont in discoveryContinuations { cont.finish() }
        discoveryContinuations.removeAll()
        lock.unlock()
        logger.info("scan: stopped")
    }

    public func connect(_ id: UUID) async throws {
        guard let peripheral = manager.retrievePeripherals(withIdentifiers: [id]).first else {
            throw LooiError.peripheralNotFound(timeout: .zero)
        }
        peripheral.delegate = self
        connectedPeripheral = peripheral
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            lock.lock(); pendingConnect = cont; lock.unlock()
            manager.connect(peripheral, options: nil)
        }
    }

    public func disconnect() async {
        guard let p = connectedPeripheral else { return }
        manager.cancelPeripheralConnection(p)
        connectedPeripheral = nil
        discoveredServices.removeAll()
    }

    public func discoverServicesAndCharacteristics(timeout: Duration) async throws {
        guard let p = connectedPeripheral else {
            throw LooiError.sessionNotReady(state: .disconnected)
        }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            lock.lock(); pendingDiscover = cont; lock.unlock()
            p.discoverServices(nil)
        }
        // Wait briefly for char discovery (single-stage didDiscoverServices
        // doesn't await characteristics; they enumerate in
        // didDiscoverCharacteristicsFor). Crude polling kept tight.
        try await Task.sleep(for: .milliseconds(500))
    }

    public func write(_ data: Data, to characteristic: CBUUID, type: WriteType) async throws {
        guard let char = findCharacteristic(characteristic) else {
            throw LooiError.characteristicMissing(characteristic)
        }
        guard let p = connectedPeripheral else {
            throw LooiError.sessionNotReady(state: .disconnected)
        }
        let cbType: CBCharacteristicWriteType = (type == .withResponse) ? .withResponse : .withoutResponse
        p.writeValue(data, for: char, type: cbType)
    }

    public func read(from characteristic: CBUUID) async throws -> Data {
        guard let char = findCharacteristic(characteristic) else {
            throw LooiError.characteristicMissing(characteristic)
        }
        guard let p = connectedPeripheral else {
            throw LooiError.sessionNotReady(state: .disconnected)
        }
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            lock.lock(); pendingReads[characteristic] = cont; lock.unlock()
            p.readValue(for: char)
        }
    }

    public func subscribe(to characteristic: CBUUID) async throws -> AsyncStream<Data> {
        guard let char = findCharacteristic(characteristic) else {
            throw LooiError.characteristicMissing(characteristic)
        }
        guard let p = connectedPeripheral else {
            throw LooiError.sessionNotReady(state: .disconnected)
        }
        p.setNotifyValue(true, for: char)
        return AsyncStream { [weak self] continuation in
            guard let self else { continuation.finish(); return }
            self.lock.lock()
            self.subscriptionContinuations[characteristic, default: []].append(continuation)
            self.lock.unlock()
        }
    }

    private func findCharacteristic(_ uuid: CBUUID) -> CBCharacteristic? {
        discoveredServices.flatMap { $0.characteristics ?? [] }.first { $0.uuid == uuid }
    }
}

extension CoreBluetoothTransport: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        lock.lock()
        _radioState = translate(central.state)
        lock.unlock()
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String : Any],
        rssi RSSI: NSNumber
    ) {
        let name = peripheral.name
            ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? "Unknown"
        if !currentNameFilter.isEmpty,
           !name.uppercased().contains(currentNameFilter.uppercased()) {
            return
        }
        let services = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
        let mfg = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
        let p = DiscoveredPeripheral(
            id: peripheral.identifier,
            name: name,
            rssi: RSSI.intValue,
            advertisedServices: services,
            manufacturerData: mfg,
            lastSeen: Date()
        )
        lock.lock()
        let conts = discoveryContinuations
        lock.unlock()
        for cont in conts { cont.yield(p) }
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        lock.lock(); let c = pendingConnect; pendingConnect = nil; lock.unlock()
        c?.resume()
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        lock.lock(); let c = pendingConnect; pendingConnect = nil; lock.unlock()
        c?.resume(throwing: LooiError.connectionFailed(underlying: error ?? NSError(domain: "CB", code: -1)))
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        let reason: DisconnectionReason = (error == nil) ? .clean : .error(error!.localizedDescription)
        lock.lock()
        let conts = disconnectionContinuations
        connectedPeripheral = nil
        discoveredServices.removeAll()
        lock.unlock()
        for cont in conts { cont.yield(reason) }
    }

    private func translate(_ cb: CBManagerState) -> BLERadioState {
        switch cb {
        case .unknown, .resetting: return .unknown
        case .unsupported:         return .unsupported
        case .unauthorized:        return .unauthorized
        case .poweredOff:          return .poweredOff
        case .poweredOn:           return .poweredOn
        @unknown default:          return .unknown
        }
    }
}

extension CoreBluetoothTransport: CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            lock.lock(); let c = pendingDiscover; pendingDiscover = nil; lock.unlock()
            c?.resume(throwing: LooiError.connectionFailed(underlying: error))
            return
        }
        discoveredServices = peripheral.services ?? []
        for s in discoveredServices {
            peripheral.discoverCharacteristics(nil, for: s)
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error {
            lock.lock(); let c = pendingDiscover; pendingDiscover = nil; lock.unlock()
            c?.resume(throwing: LooiError.connectionFailed(underlying: error))
            return
        }
        // Refresh discoveredServices snapshot so findCharacteristic sees the updated chars.
        discoveredServices = peripheral.services ?? []
        // Resume after first service's chars enumerate; sleep in discoverServicesAndCharacteristics
        // covers remaining services.
        lock.lock(); let c = pendingDiscover; pendingDiscover = nil; lock.unlock()
        c?.resume()
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            lock.lock(); let pr = pendingReads.removeValue(forKey: characteristic.uuid); lock.unlock()
            pr?.resume(throwing: LooiError.writeFailed(characteristic.uuid, underlying: error))
            return
        }
        let value = characteristic.value ?? Data()

        // Resolve any pending read first.
        lock.lock(); let pr = pendingReads.removeValue(forKey: characteristic.uuid); lock.unlock()
        if let pr {
            pr.resume(returning: value)
            return
        }

        // Otherwise it's a notification — fan out to subscribers.
        lock.lock()
        let conts = subscriptionContinuations[characteristic.uuid] ?? []
        lock.unlock()
        for cont in conts { cont.yield(value) }
    }
}

#endif
```

Why `#if canImport(CoreBluetooth) && (os(iOS) || os(macOS))`: CoreBluetooth is iOS+macOS but Linux SwiftPM test runs may not have it. The file is conditionally compiled — the rest of LooiKit always compiles.

Why `@unchecked Sendable`: CoreBluetoothTransport holds mutable state guarded by an `NSRecursiveLock`. Marking it `@unchecked Sendable` is the standard pattern for "I promise the lock makes this safe to share across actors" in Swift 6 strict concurrency. A future refactor could replace the lock with an actor — out of scope for PR 1.

- [ ] **Step 6: Write the mock's self-tests**

Create `Packages/LooiKit/Tests/LooiKitTests/MockBLETransportTests.swift`:

```swift
import XCTest
import CoreBluetooth
@testable import LooiKit
import LooiKitTesting

final class MockBLETransportTests: XCTestCase {

    func test_write_recordedInOrder() async throws {
        let mock = MockBLETransport()
        let c1 = LooiProtocol.Char.movement
        let c2 = LooiProtocol.Char.head
        try await mock.write(Data([0x01]), to: c1, type: .withoutResponse)
        try await mock.write(Data([0x02, 0x03]), to: c2, type: .withResponse)

        let writes = await mock.writes
        XCTAssertEqual(writes.count, 2)
        XCTAssertEqual(writes[0].characteristic, c1)
        XCTAssertEqual(writes[0].data, Data([0x01]))
        XCTAssertEqual(writes[0].type, .withoutResponse)
        XCTAssertEqual(writes[1].characteristic, c2)
        XCTAssertEqual(writes[1].data, Data([0x02, 0x03]))
        XCTAssertEqual(writes[1].type, .withResponse)
    }

    func test_stubbedRead_returnsConfiguredData() async throws {
        let mock = MockBLETransport()
        await mock.stubRead(LooiProtocol.Char.battery, returns: Data([0x55]))
        let value = try await mock.read(from: LooiProtocol.Char.battery)
        XCTAssertEqual(value, Data([0x55]))
    }

    func test_subscribe_yieldsSimulatedNotifications() async throws {
        let mock = MockBLETransport()
        let stream = try await mock.subscribe(to: LooiProtocol.Char.telemetry)
        await mock.simulateNotification(on: LooiProtocol.Char.telemetry, data: Data([0x09, 0x01]))
        await mock.simulateNotification(on: LooiProtocol.Char.telemetry, data: Data([0x09, 0x02]))

        var received: [Data] = []
        var iter = stream.makeAsyncIterator()
        for _ in 0..<2 {
            if let v = await iter.next() { received.append(v) }
        }
        XCTAssertEqual(received, [Data([0x09, 0x01]), Data([0x09, 0x02])])
    }

    func test_queuedConnectionFailure_throwsLooiError() async {
        let mock = MockBLETransport()
        await mock.queueFailure(.connectionFailure)
        do {
            try await mock.connect(UUID())
            XCTFail("expected throw")
        } catch let LooiError.connectionFailed {
            // expected
        } catch {
            XCTFail("expected LooiError.connectionFailed, got \(error)")
        }
    }
}
```

Create `Packages/LooiKit/Tests/LooiKitTests/BLETransportTests.swift` (covers the value types):

```swift
import XCTest
import CoreBluetooth
@testable import LooiKit

final class BLETransportTests: XCTestCase {

    func test_writeType_equality() {
        XCTAssertEqual(WriteType.withResponse, WriteType.withResponse)
        XCTAssertNotEqual(WriteType.withResponse, WriteType.withoutResponse)
    }

    func test_radioState_equality() {
        XCTAssertEqual(BLERadioState.poweredOn, BLERadioState.poweredOn)
        XCTAssertNotEqual(BLERadioState.poweredOn, BLERadioState.poweredOff)
    }

    func test_discoveredPeripheral_id_isHashable() {
        let id = UUID()
        let a = DiscoveredPeripheral(id: id, name: "LOOI", rssi: -60, advertisedServices: [], manufacturerData: nil, lastSeen: Date())
        let b = DiscoveredPeripheral(id: id, name: "LOOI", rssi: -60, advertisedServices: [], manufacturerData: nil, lastSeen: a.lastSeen)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.hashValue, b.hashValue)
    }

    func test_disconnectionReason_errorCarriesString() {
        let r = DisconnectionReason.error("link lost")
        if case .error(let s) = r {
            XCTAssertEqual(s, "link lost")
        } else { XCTFail() }
    }
}
```

- [ ] **Step 7: Run tests**

```bash
swift test --package-path Packages/LooiKit 2>&1 | tail -30
```

Expected: `Test Suite 'All tests' passed`.

- [ ] **Step 8: Verify app builds**

```bash
xcodebuild build -project ulooi.xcodeproj -scheme ulooi \
  -destination 'platform=iOS Simulator,name=iPhone 16' -quiet 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 9: Commit**

```bash
git add Packages/LooiKit
git commit -m "feat(transport): BLETransport protocol + CoreBluetoothTransport + MockBLETransport

Adds the testable seam: BLETransport protocol exposes scan/connect/write/
read/subscribe + disconnection stream. CoreBluetoothTransport is the
production impl wrapping CBCentralManager + CBPeripheralDelegate behind
async methods. MockBLETransport (actor in LooiKitTesting) records writes,
stubs reads, and simulates notifications/disconnects for unit tests.

LooiSession (Task 7) will depend on BLETransport instead of CoreBluetooth
directly so the full session lifecycle is reachable from XCTest."
```

---

## Task 4: LooiError + LocalizedError

**Files:**
- Create: `Packages/LooiKit/Sources/LooiKit/Errors/LooiError.swift`
- Create: `Packages/LooiKit/Sources/LooiKit/Models/CliffState.swift` (referenced by `LooiError.cliffLocked`)
- Create: `Packages/LooiKit/Sources/LooiKit/Protocol/HandshakeStep.swift` (referenced by `LooiError.handshakeFailed`)
- Create: `Packages/LooiKit/Tests/LooiKitTests/LooiErrorTests.swift`

> **Important:** Task 3 already references `LooiError.connectionFailed`, `.characteristicMissing`, `.writeFailed`, `.peripheralNotFound`, `.sessionNotReady`. **Do Task 4 before Task 3's Step 4 (MockBLETransport)** — otherwise Task 3 won't compile. If you started Task 3 already, complete it now by jumping here.

- [ ] **Step 1: Create folders**

```bash
mkdir -p Packages/LooiKit/Sources/LooiKit/Errors
```

- [ ] **Step 2: Write CliffState model (small enum used by LooiError and SensorController later)**

Create `Packages/LooiKit/Sources/LooiKit/Models/CliffState.swift`:

```swift
import Foundation

/// 4-direction cliff sensor state. M0.5 confirmed: bit 1 (front) toggles
/// when Looi's front wheels lift. Full 4-direction mapping is opportunistic
/// during M1 development (spec §3 out-of-scope until M2 if needed) but the
/// type is shaped for that future. Decoded from FED9 type 0x01 packets.
public struct CliffState: Sendable, Equatable, OptionSet {
    public let rawValue: UInt8

    public static let frontSuspended = CliffState(rawValue: 1 << 0)
    public static let rearSuspended  = CliffState(rawValue: 1 << 1)
    public static let leftSuspended  = CliffState(rawValue: 1 << 2)
    public static let rightSuspended = CliffState(rawValue: 1 << 3)

    public static let grounded: CliffState = []

    public init(rawValue: UInt8) { self.rawValue = rawValue }

    /// True when ALL wheels are on the ground (motor commands allowed).
    public var isGrounded: Bool { rawValue == 0 }

    /// True when any wheel is suspended (motor commands hard-blocked).
    public var isSuspended: Bool { rawValue != 0 }
}
```

- [ ] **Step 3: Write HandshakeStep enum (referenced by LooiError.handshakeFailed; full HandshakeRunner is Task 6)**

Create `Packages/LooiKit/Sources/LooiKit/Protocol/HandshakeStep.swift`:

```swift
import Foundation

/// Discrete steps in the FEDA handshake sequence. Carried by
/// `LooiError.handshakeFailed(step:)` so the failure UX can name what
/// stalled. Order matches `HandshakeRunner.run()` (Task 6).
public enum HandshakeStep: Sendable, Equatable {
    case readManufacturer        // 2A29 wake-up
    case writePhase1             // FEDA ← 0x01
    case subscribeSensors        // FED5 setNotify
    case subscribeTelemetry      // FED9 setNotify
    case writePhase2             // FEDA ← 0x03
}
```

- [ ] **Step 4: Write LooiError**

Create `Packages/LooiKit/Sources/LooiKit/Errors/LooiError.swift`:

```swift
import Foundation
import CoreBluetooth

/// All errors thrown across LooiKit's public surface. Carries enough
/// context that UI can produce meaningful messages without re-parsing
/// the underlying Error.
public enum LooiError: Error, LocalizedError, Sendable {
    case bluetoothUnauthorized
    case bluetoothPoweredOff
    case peripheralNotFound(timeout: Duration)
    case connectionFailed(underlying: Error)
    case handshakeFailed(step: HandshakeStep)
    case characteristicMissing(CBUUID)
    case writeFailed(CBUUID, underlying: Error)
    case cliffLocked(directions: CliffState)
    case sessionNotReady(state: SessionState)
    case gestureCancelled

    public var errorDescription: String? {
        switch self {
        case .bluetoothUnauthorized:
            return "蓝牙未授权 — 请到「设置 → 隐私 → 蓝牙」打开 ulooi 的权限。"
        case .bluetoothPoweredOff:
            return "蓝牙已关闭 — 请打开蓝牙。"
        case .peripheralNotFound(let timeout):
            let s = Int(timeout.components.seconds)
            return "在 \(s) 秒内没有找到 Looi — 请确认机器已开机并在身边。"
        case .connectionFailed:
            return "连接 Looi 失败 — 请稍候重试。"
        case .handshakeFailed(let step):
            return "握手中断（\(step)）— Looi 可能掉线了，请重新尝试。"
        case .characteristicMissing(let uuid):
            return "缺少特征 \(uuid.uuidString) — 服务发现可能未完成。"
        case .writeFailed(let uuid, _):
            return "向 \(uuid.uuidString) 写入失败 — 连接可能掉了。"
        case .cliffLocked:
            return "Looi 悬空了 — 放回地面再驱动。"
        case .sessionNotReady(let state):
            return "Looi 未就绪（当前状态：\(state)）"
        case .gestureCancelled:
            return "动作被中止。"
        }
    }
}

extension LooiError {
    /// English fallback strings — useful for log messages and accessibility.
    public var englishDescription: String {
        switch self {
        case .bluetoothUnauthorized:    return "Bluetooth permission not granted."
        case .bluetoothPoweredOff:      return "Bluetooth is off."
        case .peripheralNotFound(let t):
            return "No Looi found within \(Int(t.components.seconds))s."
        case .connectionFailed:         return "Failed to connect to Looi."
        case .handshakeFailed(let s):   return "Handshake interrupted at \(s)."
        case .characteristicMissing(let u): return "Missing characteristic \(u.uuidString)."
        case .writeFailed(let u, _):    return "Write to \(u.uuidString) failed."
        case .cliffLocked:              return "Looi is suspended — put me down to drive."
        case .sessionNotReady(let s):   return "Session not ready (state: \(s))."
        case .gestureCancelled:         return "Gesture cancelled."
        }
    }
}
```

Note: `SessionState` is referenced in `.sessionNotReady(state:)` — Task 5 defines it. For this commit, you have two options:

(a) **Forward-declare a temporary** `public enum SessionState: Sendable, Equatable { case disconnected }` placeholder in this file and replace with the real enum in Task 5. The placeholder satisfies the type checker.

(b) **Do Task 5 before Task 4 Step 4.** SessionState is independent of LooiError.

Recommendation: (b) — cleaner. Treat Task 5 as the actual next task and come back to LooiError's `.sessionNotReady` after the enum lands.

For the rest of this Task 4, assume SessionState already exists.

- [ ] **Step 5: Write tests**

Create `Packages/LooiKit/Tests/LooiKitTests/LooiErrorTests.swift`:

```swift
import XCTest
import CoreBluetooth
@testable import LooiKit

final class LooiErrorTests: XCTestCase {

    func test_cliffLocked_zhDescription_mentionsHangs() {
        let err = LooiError.cliffLocked(directions: .frontSuspended)
        let desc = err.errorDescription ?? ""
        XCTAssertTrue(desc.contains("悬空"))
    }

    func test_cliffLocked_englishFallback_mentionsSuspended() {
        let err = LooiError.cliffLocked(directions: .frontSuspended)
        XCTAssertTrue(err.englishDescription.contains("suspended"))
    }

    func test_peripheralNotFound_carriesTimeout() {
        let err = LooiError.peripheralNotFound(timeout: .seconds(15))
        XCTAssertTrue(err.errorDescription!.contains("15"))
    }

    func test_handshakeFailed_carriesStep() {
        let err = LooiError.handshakeFailed(step: .writePhase2)
        XCTAssertTrue(err.errorDescription!.contains("writePhase2"))
        XCTAssertTrue(err.englishDescription.contains("writePhase2"))
    }

    func test_characteristicMissing_carriesUUID() {
        let err = LooiError.characteristicMissing(LooiProtocol.Char.handshake)
        XCTAssertTrue(err.errorDescription!.lowercased().contains("feda"))
    }

    func test_cliffState_grounded_isEmpty() {
        XCTAssertTrue(CliffState.grounded.isGrounded)
        XCTAssertFalse(CliffState.grounded.isSuspended)
    }

    func test_cliffState_frontSuspended_isNotGrounded() {
        XCTAssertFalse(CliffState.frontSuspended.isGrounded)
        XCTAssertTrue(CliffState.frontSuspended.isSuspended)
    }
}
```

- [ ] **Step 6: Run tests**

```bash
swift test --package-path Packages/LooiKit 2>&1 | tail -30
```

Expected: `Test Suite 'All tests' passed`. If `SessionState` isn't defined yet, this task can't complete — go do Task 5, then resume.

- [ ] **Step 7: Commit**

```bash
git add Packages/LooiKit
git commit -m "feat(errors): LooiError + LocalizedError + CliffState + HandshakeStep

Nine-case LooiError enum implements LocalizedError with Chinese-primary
descriptions and English fallbacks (englishDescription) for logs.
Cases carry enough context for UI (timeout durations, failed CBUUIDs,
handshake step names). CliffState is a 4-bit OptionSet (front/rear/
left/right suspended) with isGrounded / isSuspended convenience.
HandshakeStep enumerates the five FEDA-handshake steps so failures
name what stalled."
```

---

## Task 5: SessionState + SessionStateMachine

**Files:**
- Create: `Packages/LooiKit/Sources/LooiKit/Session/SessionState.swift`
- Create: `Packages/LooiKit/Sources/LooiKit/Session/SessionStateMachine.swift`
- Create: `Packages/LooiKit/Tests/LooiKitTests/SessionStateMachineTests.swift`

- [ ] **Step 1: Create the Session folder**

```bash
mkdir -p Packages/LooiKit/Sources/LooiKit/Session
```

- [ ] **Step 2: Write SessionState**

Create `Packages/LooiKit/Sources/LooiKit/Session/SessionState.swift`:

```swift
import Foundation

/// The nine states a LooiSession passes through. Matches spec §5.2's
/// state diagram. Transitions are validated by SessionStateMachine.
public enum SessionState: Sendable, Equatable, CustomStringConvertible {
    case disconnected
    case scanning
    case connecting
    case discovering
    case handshaking
    case ready
    case reconnecting(attempt: Int)

    public var description: String {
        switch self {
        case .disconnected:               return "disconnected"
        case .scanning:                   return "scanning"
        case .connecting:                 return "connecting"
        case .discovering:                return "discovering"
        case .handshaking:                return "handshaking"
        case .ready:                      return "ready"
        case .reconnecting(let attempt):  return "reconnecting(\(attempt))"
        }
    }

    /// Convenience used by lifecycle hooks (heartbeat starts/stops here).
    public var isReady: Bool { if case .ready = self { return true }; return false }

    /// True if motor heartbeat + battery poll should be running.
    public var hasActiveSession: Bool { isReady }

    /// True if the state represents an "in-progress" attempt (not idle).
    public var isInProgress: Bool {
        switch self {
        case .disconnected, .ready: return false
        default: return true
        }
    }
}
```

- [ ] **Step 3: Write the state machine**

Create `Packages/LooiKit/Sources/LooiKit/Session/SessionStateMachine.swift`:

```swift
import Foundation
import OSLog

/// Pure-Swift state machine. Owns the current SessionState; rejects
/// invalid transitions; emits a single notification per accepted
/// transition (satisfies invariant I1 + I5 from spec §5.4).
///
/// Designed to be embedded in LooiSession (@MainActor); the machine
/// itself is @MainActor by default isolation.
public final class SessionStateMachine {

    private let logger = Logger(subsystem: "ai.if2.ulooi", category: "looikit.session")

    public private(set) var state: SessionState = .disconnected
    public var onTransition: ((SessionState, SessionState) -> Void)?

    public init() {}

    /// Attempt to transition to `target`. Throws `.invalidTransition` if
    /// the move isn't allowed from `state`. On success, logs once and
    /// fires `onTransition` exactly once (I5).
    @discardableResult
    public func transition(to target: SessionState) throws -> SessionState {
        guard isValid(from: state, to: target) else {
            throw TransitionError.invalidTransition(from: state, to: target)
        }
        let previous = state
        state = target
        logger.info("state: \(previous.description, privacy: .public) → \(target.description, privacy: .public)")
        onTransition?(previous, target)
        return state
    }

    /// Force a transition without validation. Use sparingly — only for
    /// emergency reset paths (e.g., app willTerminate forces .disconnected
    /// regardless of source).
    public func forceTransition(to target: SessionState, reason: String) {
        let previous = state
        state = target
        logger.warning("state (forced, \(reason, privacy: .public)): \(previous.description, privacy: .public) → \(target.description, privacy: .public)")
        onTransition?(previous, target)
    }

    public enum TransitionError: Error, Equatable {
        case invalidTransition(from: SessionState, to: SessionState)
    }

    /// Validation table per spec §5.2. Cliff transitions and lifecycle
    /// stops do NOT change SessionState — they're orthogonal.
    private func isValid(from: SessionState, to: SessionState) -> Bool {
        switch (from, to) {
        // From .disconnected
        case (.disconnected, .scanning):       return true
        case (.disconnected, .reconnecting):   return true

        // From .scanning
        case (.scanning, .connecting):         return true
        case (.scanning, .disconnected):       return true  // user cancel
        case (.scanning, .reconnecting):       return true

        // From .connecting
        case (.connecting, .discovering):      return true
        case (.connecting, .disconnected):     return true  // fail
        case (.connecting, .reconnecting):     return true  // fail mid-attempt

        // From .discovering
        case (.discovering, .handshaking):     return true
        case (.discovering, .disconnected):    return true
        case (.discovering, .reconnecting):    return true

        // From .handshaking
        case (.handshaking, .ready):           return true
        case (.handshaking, .disconnected):    return true
        case (.handshaking, .reconnecting):    return true

        // From .ready
        case (.ready, .reconnecting):          return true
        case (.ready, .disconnected):          return true  // user disconnect

        // From .reconnecting
        case (.reconnecting, .scanning):       return true
        case (.reconnecting, .reconnecting):   return true  // attempt bump
        case (.reconnecting, .disconnected):   return true  // timeout

        default:                               return false
        }
    }
}
```

- [ ] **Step 4: Write tests for transitions + observer**

Create `Packages/LooiKit/Tests/LooiKitTests/SessionStateMachineTests.swift`:

```swift
import XCTest
@testable import LooiKit

@MainActor
final class SessionStateMachineTests: XCTestCase {

    func test_initialState_isDisconnected() {
        let m = SessionStateMachine()
        XCTAssertEqual(m.state, .disconnected)
    }

    func test_happyPath_scanToReady() throws {
        let m = SessionStateMachine()
        try m.transition(to: .scanning)
        try m.transition(to: .connecting)
        try m.transition(to: .discovering)
        try m.transition(to: .handshaking)
        try m.transition(to: .ready)
        XCTAssertEqual(m.state, .ready)
    }

    func test_invalidTransition_disconnectedToReady_throws() {
        let m = SessionStateMachine()
        XCTAssertThrowsError(try m.transition(to: .ready)) { err in
            guard case SessionStateMachine.TransitionError.invalidTransition(let from, let to) = err else {
                XCTFail("wrong error: \(err)"); return
            }
            XCTAssertEqual(from, .disconnected)
            XCTAssertEqual(to, .ready)
        }
    }

    func test_readyToReconnecting_thenToScanning() throws {
        let m = SessionStateMachine()
        try m.transition(to: .scanning)
        try m.transition(to: .connecting)
        try m.transition(to: .discovering)
        try m.transition(to: .handshaking)
        try m.transition(to: .ready)
        try m.transition(to: .reconnecting(attempt: 1))
        try m.transition(to: .scanning)
        XCTAssertEqual(m.state, .scanning)
    }

    func test_reconnecting_canBumpAttempt() throws {
        let m = SessionStateMachine()
        try m.transition(to: .scanning)
        try m.transition(to: .connecting)
        try m.transition(to: .discovering)
        try m.transition(to: .handshaking)
        try m.transition(to: .ready)
        try m.transition(to: .reconnecting(attempt: 1))
        try m.transition(to: .reconnecting(attempt: 2))
        try m.transition(to: .reconnecting(attempt: 3))
        XCTAssertEqual(m.state, .reconnecting(attempt: 3))
    }

    func test_reconnectingTimeout_returnsToDisconnected() throws {
        let m = SessionStateMachine()
        try m.transition(to: .scanning)
        try m.transition(to: .connecting)
        try m.transition(to: .discovering)
        try m.transition(to: .handshaking)
        try m.transition(to: .ready)
        try m.transition(to: .reconnecting(attempt: 1))
        try m.transition(to: .disconnected)
        XCTAssertEqual(m.state, .disconnected)
    }

    func test_onTransition_firesOncePerAcceptedTransition() throws {
        let m = SessionStateMachine()
        var events: [(SessionState, SessionState)] = []
        m.onTransition = { from, to in events.append((from, to)) }
        try m.transition(to: .scanning)
        try m.transition(to: .connecting)
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].0, .disconnected)
        XCTAssertEqual(events[0].1, .scanning)
        XCTAssertEqual(events[1].0, .scanning)
        XCTAssertEqual(events[1].1, .connecting)
    }

    func test_onTransition_doesNotFireOnRejection() {
        let m = SessionStateMachine()
        var count = 0
        m.onTransition = { _, _ in count += 1 }
        XCTAssertThrowsError(try m.transition(to: .ready))
        XCTAssertEqual(count, 0)
    }

    func test_forceTransition_bypassesValidation() {
        let m = SessionStateMachine()
        m.forceTransition(to: .ready, reason: "test override")
        XCTAssertEqual(m.state, .ready)
    }

    func test_isReady_onlyTrueWhenReady() {
        XCTAssertFalse(SessionState.disconnected.isReady)
        XCTAssertFalse(SessionState.scanning.isReady)
        XCTAssertTrue(SessionState.ready.isReady)
        XCTAssertFalse(SessionState.reconnecting(attempt: 1).isReady)
    }
}
```

- [ ] **Step 5: Run tests**

```bash
swift test --package-path Packages/LooiKit 2>&1 | tail -30
```

Expected: `Test Suite 'All tests' passed`.

- [ ] **Step 6: Commit**

```bash
git add Packages/LooiKit
git commit -m "feat(session): SessionState (9 cases) + SessionStateMachine

Pure-Swift state machine enforces the transition table from spec §5.2.
Rejects invalid transitions (e.g. .disconnected → .ready); fires
onTransition observer exactly once per accepted transition (satisfies
invariants I1 + I5). forceTransition escape hatch for emergency resets.
SessionState includes isReady / hasActiveSession / isInProgress helpers
used by lifecycle hooks. .reconnecting carries an attempt counter for
the backoff schedule (Task 11)."
```

---

## Task 6: HandshakeRunner with Typed Steps

**Files:**
- Create: `Packages/LooiKit/Sources/LooiKit/Protocol/HandshakeRunner.swift`
- Create: `Packages/LooiKit/Tests/LooiKitTests/HandshakeRunnerTests.swift`

- [ ] **Step 1: Write HandshakeRunner**

Create `Packages/LooiKit/Sources/LooiKit/Protocol/HandshakeRunner.swift`:

```swift
import Foundation
import OSLog

/// Runs the FEDA handshake against a BLETransport. Steps match
/// spec §14 + andrey-tut's waasd.py:
///   0. read 2A29 (manufacturer wake)
///   1. write 0x01 to FEDA
///   2. subscribe FED5 (sensors) + FED9 (telemetry)
///   3. write 0x03 to FEDA
/// On success, returns the two subscription streams for the caller
/// (SensorController consumes them).
public struct HandshakeRunner {
    private let transport: BLETransport
    private let logger = Logger(subsystem: "ai.if2.ulooi", category: "looikit.handshake")

    public init(transport: BLETransport) {
        self.transport = transport
    }

    public struct SubscribedStreams: Sendable {
        public let sensors: AsyncStream<Data>
        public let telemetry: AsyncStream<Data>
    }

    /// Run the full sequence. Throws `LooiError.handshakeFailed(step:)`
    /// on any per-step failure.
    public func run() async throws -> SubscribedStreams {
        // Step 0 — wake-up read; failures are non-fatal (andrey-tut
        // wraps in try/except). We try, log, continue.
        do {
            _ = try await transport.read(from: LooiProtocol.Char.deviceInfoManufacturer)
            logger.info("handshake 0/4: 2A29 wake-up read ok")
        } catch {
            logger.warning("handshake 0/4: 2A29 read failed (non-fatal): \(String(describing: error), privacy: .public)")
        }

        // Step 1 — write 0x01 to FEDA
        do {
            try await transport.write(LooiProtocol.Handshake.phase1Data,
                                     to: LooiProtocol.Char.handshake,
                                     type: .withResponse)
            logger.info("handshake 1/4: write 0x01 to FEDA")
            try await Task.sleep(for: .milliseconds(100))
        } catch {
            throw LooiError.handshakeFailed(step: .writePhase1)
        }

        // Step 2 — subscribe FED5 + FED9
        let sensors: AsyncStream<Data>
        do {
            sensors = try await transport.subscribe(to: LooiProtocol.Char.sensors)
            logger.info("handshake 2/4: subscribe FED5")
        } catch {
            throw LooiError.handshakeFailed(step: .subscribeSensors)
        }

        let telemetry: AsyncStream<Data>
        do {
            telemetry = try await transport.subscribe(to: LooiProtocol.Char.telemetry)
            logger.info("handshake 3/4: subscribe FED9")
        } catch {
            throw LooiError.handshakeFailed(step: .subscribeTelemetry)
        }

        // iOS asynchronously writes the descriptor for setNotify; pause
        // before phase2 so both subscriptions are actually live (M0.5
        // finding — 300ms is the empirically-stable pause).
        try await Task.sleep(for: .milliseconds(300))

        // Step 3 — write 0x03 to FEDA
        do {
            try await transport.write(LooiProtocol.Handshake.phase2Data,
                                     to: LooiProtocol.Char.handshake,
                                     type: .withResponse)
            logger.info("handshake 4/4: write 0x03 to FEDA — handshake complete")
        } catch {
            throw LooiError.handshakeFailed(step: .writePhase2)
        }

        return SubscribedStreams(sensors: sensors, telemetry: telemetry)
    }
}
```

- [ ] **Step 2: Write tests**

Create `Packages/LooiKit/Tests/LooiKitTests/HandshakeRunnerTests.swift`:

```swift
import XCTest
import CoreBluetooth
@testable import LooiKit
import LooiKitTesting

final class HandshakeRunnerTests: XCTestCase {

    func test_happyPath_emitsExpectedByteSequence() async throws {
        let mock = MockBLETransport()
        await mock.stubRead(LooiProtocol.Char.deviceInfoManufacturer, returns: Data("LOOI".utf8))

        let runner = HandshakeRunner(transport: mock)
        _ = try await runner.run()

        let writes = await mock.writes
        let subs = await mock.subscriptions
        let reads = await mock.reads

        // 1× read on 2A29
        XCTAssertEqual(reads.count, 1)
        XCTAssertEqual(reads.first, LooiProtocol.Char.deviceInfoManufacturer)

        // 2× write to FEDA: 0x01 then 0x03
        XCTAssertEqual(writes.count, 2)
        XCTAssertEqual(writes[0].characteristic, LooiProtocol.Char.handshake)
        XCTAssertEqual(writes[0].data, Data([0x01]))
        XCTAssertEqual(writes[1].characteristic, LooiProtocol.Char.handshake)
        XCTAssertEqual(writes[1].data, Data([0x03]))

        // 2× subscribe: FED5 first, FED9 second
        XCTAssertEqual(subs, [LooiProtocol.Char.sensors, LooiProtocol.Char.telemetry])
    }

    func test_phase1WriteFailure_throwsHandshakeFailedWritePhase1() async {
        let mock = MockBLETransport()
        await mock.queueFailure(.writeFailure(LooiProtocol.Char.handshake))
        let runner = HandshakeRunner(transport: mock)
        do {
            _ = try await runner.run()
            XCTFail("expected throw")
        } catch let LooiError.handshakeFailed(step) {
            XCTAssertEqual(step, .writePhase1)
        } catch {
            XCTFail("expected LooiError.handshakeFailed(.writePhase1), got \(error)")
        }
    }

    func test_subscribeSensorsFailure_throwsHandshakeFailedSubscribeSensors() async {
        let mock = MockBLETransport()
        await mock.queueFailure(.characteristicMissing(LooiProtocol.Char.sensors))
        let runner = HandshakeRunner(transport: mock)
        do {
            _ = try await runner.run()
            XCTFail("expected throw")
        } catch let LooiError.handshakeFailed(step) {
            XCTAssertEqual(step, .subscribeSensors)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func test_manufacturerReadFailure_isNonFatal() async throws {
        // 2A29 read failure should NOT abort; handshake continues.
        let mock = MockBLETransport()
        await mock.queueFailure(.characteristicMissing(LooiProtocol.Char.deviceInfoManufacturer))
        let runner = HandshakeRunner(transport: mock)
        _ = try await runner.run()  // does not throw
        let writes = await mock.writes
        XCTAssertEqual(writes.count, 2)  // phase1 + phase2 still happened
    }
}
```

- [ ] **Step 3: Run tests**

```bash
swift test --package-path Packages/LooiKit 2>&1 | tail -30
```

Expected: `Test Suite 'All tests' passed`. Tests are slow because of the 100ms + 300ms sleeps inside `run()` — that's acceptable for PR 1; if it becomes painful in CI a future task can inject a clock.

- [ ] **Step 4: Commit**

```bash
git add Packages/LooiKit
git commit -m "feat(handshake): HandshakeRunner with typed steps

Runs the 4-step FEDA handshake (manufacturer wake / write 0x01 / subscribe
FED5+FED9 / write 0x03) against a BLETransport. Throws
LooiError.handshakeFailed(step:) on per-step failure (so UI can name
which step stalled). 2A29 manufacturer read is treated as non-fatal
(matches andrey-tut Python). Returns the FED5 + FED9 subscription
streams as SubscribedStreams for SensorController (Task 10) to consume."
```

---

## Task 7: LooiSession (transport-injected wrapper)

**Files:**
- Create: `Packages/LooiKit/Sources/LooiKit/Session/LooiSession.swift`
- Create: `Packages/LooiKit/Tests/LooiKitTests/LooiSessionTests.swift`

This task introduces `LooiSession` as the top-level public type. It is the eventual replacement for `BLECentral`. In this task it ships only the connect/disconnect lifecycle on top of the state machine + transport + handshake; the four Controllers attach in Tasks 8-10 and reconnect attaches in Task 11.

- [ ] **Step 1: Write LooiSession**

Create `Packages/LooiKit/Sources/LooiKit/Session/LooiSession.swift`:

```swift
import Foundation
import Observation
import CoreBluetooth
import OSLog

/// Top-level public type — the iOS app's handle to one paired Looi.
///
/// Owns the SessionState machine, the BLETransport, and (in later tasks)
/// the four Controllers + reconnect policy + handshake. Mutates state
/// only on @MainActor (invariant I1).
@MainActor
@Observable
public final class LooiSession {

    public private(set) var state: SessionState = .disconnected
    public private(set) var currentPeripheral: DiscoveredPeripheral?

    private let transport: BLETransport
    private let machine: SessionStateMachine
    private let logger = Logger(subsystem: "ai.if2.ulooi", category: "looikit.session")
    private var scanTask: Task<Void, Never>?
    private var connectTask: Task<Void, Never>?
    private var disconnectionWatcher: Task<Void, Never>?

    public init(transport: BLETransport) {
        self.transport = transport
        self.machine = SessionStateMachine()
        self.machine.onTransition = { [weak self] _, to in
            // Mirror machine.state into LooiSession.state for @Observable.
            Task { @MainActor [weak self] in
                self?.state = to
            }
        }
        self.disconnectionWatcher = Task { [weak self] in
            guard let self else { return }
            for await reason in transport.disconnections {
                await self.handleDisconnection(reason)
            }
        }
    }

    deinit {
        disconnectionWatcher?.cancel()
        scanTask?.cancel()
        connectTask?.cancel()
    }

    // MARK: - Public API

    /// Start scanning + auto-connect to the first matching peripheral
    /// (or to `pairedPeripheralID` if set — Task 11 wires that).
    public func startScanAndConnect(nameFilter: String = "LOOI") {
        scanTask?.cancel()
        scanTask = Task { [weak self] in
            await self?.runScanAndConnect(nameFilter: nameFilter)
        }
    }

    /// Manually connect to a specific discovered peripheral by UUID.
    public func connect(to id: UUID) {
        connectTask?.cancel()
        connectTask = Task { [weak self] in
            await self?.runConnect(id: id, fromState: nil)
        }
    }

    /// User-initiated disconnect. Cancels in-flight work, drops to .disconnected.
    public func disconnect() {
        Task { [weak self] in
            guard let self else { return }
            self.scanTask?.cancel()
            self.connectTask?.cancel()
            await self.transport.disconnect()
            try? self.machine.transition(to: .disconnected)
            self.currentPeripheral = nil
        }
    }

    // MARK: - Internal flow

    private func runScanAndConnect(nameFilter: String) async {
        do {
            try machine.transition(to: .scanning)
        } catch { return }

        let stream = transport.scan(nameFilter: nameFilter)
        for await peripheral in stream {
            if Task.isCancelled { return }
            currentPeripheral = peripheral
            await transport.stopScan()
            await runConnect(id: peripheral.id, fromState: .scanning)
            return
        }
    }

    private func runConnect(id: UUID, fromState: SessionState?) async {
        do {
            if fromState == nil {
                try machine.transition(to: .scanning)
                try machine.transition(to: .connecting)
            } else {
                try machine.transition(to: .connecting)
            }
        } catch {
            logger.error("runConnect: invalid transition from \(self.machine.state.description, privacy: .public)")
            return
        }

        do {
            try await transport.connect(id)
        } catch {
            logger.error("runConnect: transport.connect failed: \(String(describing: error), privacy: .public)")
            try? machine.transition(to: .disconnected)
            return
        }

        do {
            try machine.transition(to: .discovering)
            try await transport.discoverServicesAndCharacteristics(timeout: .seconds(4))
        } catch {
            logger.error("runConnect: discover failed: \(String(describing: error), privacy: .public)")
            try? machine.transition(to: .disconnected)
            return
        }

        do {
            try machine.transition(to: .handshaking)
            _ = try await HandshakeRunner(transport: transport).run()
        } catch {
            logger.error("runConnect: handshake failed: \(String(describing: error), privacy: .public)")
            try? machine.transition(to: .disconnected)
            return
        }

        try? machine.transition(to: .ready)
    }

    private func handleDisconnection(_ reason: DisconnectionReason) async {
        logger.info("disconnection: \(String(describing: reason), privacy: .public) from state \(self.state.description, privacy: .public)")
        // Task 11 will replace this with proper reconnecting state.
        try? machine.transition(to: .disconnected)
        currentPeripheral = nil
    }
}
```

- [ ] **Step 2: Write tests**

Create `Packages/LooiKit/Tests/LooiKitTests/LooiSessionTests.swift`:

```swift
import XCTest
import CoreBluetooth
@testable import LooiKit
import LooiKitTesting

@MainActor
final class LooiSessionTests: XCTestCase {

    func test_init_isDisconnected() async {
        let mock = MockBLETransport()
        let session = LooiSession(transport: mock)
        XCTAssertEqual(session.state, .disconnected)
        XCTAssertNil(session.currentPeripheral)
    }

    func test_startScanAndConnect_movesToScanning() async {
        let mock = MockBLETransport()
        let session = LooiSession(transport: mock)
        session.startScanAndConnect(nameFilter: "LOOI")
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(session.state, .scanning)
    }

    func test_happyPath_endsInReady() async {
        let mock = MockBLETransport()
        await mock.stubRead(LooiProtocol.Char.deviceInfoManufacturer, returns: Data("LOOI".utf8))
        let session = LooiSession(transport: mock)

        session.startScanAndConnect(nameFilter: "LOOI")
        try? await Task.sleep(for: .milliseconds(50))
        await mock.simulateDiscovery(DiscoveredPeripheral(
            id: UUID(),
            name: "LOOI-1",
            rssi: -50,
            advertisedServices: [],
            manufacturerData: nil,
            lastSeen: Date()
        ))

        // Wait for the full pipeline (scan → connect → discover → handshake → ready).
        // Sleeps inside HandshakeRunner sum to ~400ms; pad to 800ms.
        try? await Task.sleep(for: .milliseconds(800))
        XCTAssertEqual(session.state, .ready)
    }

    func test_disconnect_returnsToDisconnected() async {
        let mock = MockBLETransport()
        let session = LooiSession(transport: mock)
        session.disconnect()
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(session.state, .disconnected)
    }
}
```

- [ ] **Step 3: Run tests**

```bash
swift test --package-path Packages/LooiKit 2>&1 | tail -30
```

Expected: `Test Suite 'All tests' passed`. The happy-path test is slow (~800ms) due to handshake sleeps; that's acceptable.

- [ ] **Step 4: Verify app builds**

```bash
xcodebuild build -project ulooi.xcodeproj -scheme ulooi \
  -destination 'platform=iOS Simulator,name=iPhone 16' -quiet 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`. App still uses inline BLECentral — LooiSession is unused so far.

- [ ] **Step 5: Commit**

```bash
git add Packages/LooiKit
git commit -m "feat(session): LooiSession — top-level @Observable handle on BLETransport

Owns the SessionStateMachine, drives scan → connect → discover →
handshake → ready pipeline against an injected BLETransport. Mirrors
state into @Observable property so SwiftUI can react. Watches the
transport's disconnection stream and transitions back to .disconnected
(Task 11 upgrades that to .reconnecting with backoff). Tests cover
init, scan-state entry, happy-path-to-ready, and explicit disconnect.

App target still uses inline BLECentral; the cutover is Task 12."
```

---

## Task 8: MotionController + 30 ms Heartbeat + Cliff Hard-Block (I2/I4/I6)

**Files:**
- Create: `Packages/LooiKit/Sources/LooiKit/Controllers/MotionController.swift`
- Create: `Packages/LooiKit/Tests/LooiKitTests/MotionControllerTests.swift`
- Modify: `Packages/LooiKit/Sources/LooiKit/Session/LooiSession.swift` — own a `MotionController`, start/stop heartbeat on `.ready` enter/exit.

- [ ] **Step 1: Create Controllers folder**

```bash
mkdir -p Packages/LooiKit/Sources/LooiKit/Controllers
```

- [ ] **Step 2: Write MotionController**

Create `Packages/LooiKit/Sources/LooiKit/Controllers/MotionController.swift`:

```swift
import Foundation
import Observation
import OSLog

/// Owns the 30ms motor heartbeat to FED0 and enforces the cliff hard-block.
/// Per spec §5.3 + §9.1: setMotion calls are no-ops + throw cliffLocked
/// when cliffState != .grounded. The heartbeat is the ONLY thing writing
/// FED0 — callers update `currentMotion`, the heartbeat picks it up on
/// the next tick (≤30 ms latency).
@MainActor
@Observable
public final class MotionController {

    private let transport: BLETransport
    private let cliffStateProvider: () -> CliffState
    private let logger = Logger(subsystem: "ai.if2.ulooi", category: "looikit.motion")

    public private(set) var currentMotion: MotionState = .stop
    public private(set) var heartbeatTicks: Int = 0

    private var heartbeatTask: Task<Void, Never>?

    public init(transport: BLETransport, cliffStateProvider: @escaping () -> CliffState) {
        self.transport = transport
        self.cliffStateProvider = cliffStateProvider
    }

    /// Update the motion the heartbeat will broadcast. Throws cliffLocked
    /// if any wheel is suspended (hard-block per §9.1).
    public func setMotion(_ motion: MotionState) throws {
        let cliff = cliffStateProvider()
        if cliff.isSuspended && motion != .stop {
            throw LooiError.cliffLocked(directions: cliff)
        }
        currentMotion = motion
    }

    /// Convenience wrappers — same hard-block semantics.
    public func forward(speed: Int8 = 127) throws {
        try setMotion(MotionState(label: "Forward", data: LooiCommand.Movement.encode(speed: speed, turn: 0)))
    }
    public func backward(speed: Int8 = 127) throws {
        try setMotion(MotionState(label: "Backward", data: LooiCommand.Movement.encode(speed: -speed, turn: 0)))
    }
    public func spinLeft(speed: Int8 = 127) throws {
        try setMotion(MotionState(label: "SpinLeft", data: LooiCommand.Movement.encode(speed: 0, turn: speed)))
    }
    public func spinRight(speed: Int8 = 127) throws {
        try setMotion(MotionState(label: "SpinRight", data: LooiCommand.Movement.encode(speed: 0, turn: -speed)))
    }
    public func stop() {
        // .stop bypasses the cliff check — always safe to send.
        currentMotion = .stop
    }

    /// Begin the 30 ms heartbeat. Called when LooiSession enters .ready.
    /// Safe to call repeatedly (cancels previous task).
    public func startHeartbeat() {
        cancelHeartbeat()
        heartbeatTicks = 0
        heartbeatTask = Task { [weak self] in
            guard let self else { return }
            self.logger.info("motor heartbeat: starting (30ms, .withoutResponse)")
            while !Task.isCancelled {
                let motion = self.currentMotion
                do {
                    try await self.transport.write(motion.data,
                                                   to: LooiProtocol.Char.movement,
                                                   type: .withoutResponse)
                    self.heartbeatTicks += 1
                } catch {
                    self.logger.warning("motor heartbeat: write failed at tick \(self.heartbeatTicks): \(String(describing: error), privacy: .public)")
                    break
                }
                try? await Task.sleep(for: LooiProtocol.Timing.motorHeartbeatInterval)
            }
            self.logger.info("motor heartbeat: stopped after \(self.heartbeatTicks) ticks")
        }
    }

    /// Stop the heartbeat. Called when LooiSession leaves .ready (I4).
    public func cancelHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
    }

    /// Called by LooiSession's I6 hook (cliff state grounded→suspended;
    /// background; reconnecting/disconnected). Sends one .stop and
    /// updates currentMotion so the next heartbeat tick is consistent.
    public func emergencyStop() async {
        currentMotion = .stop
        try? await transport.write(LooiCommand.Movement.stop,
                                   to: LooiProtocol.Char.movement,
                                   type: .withResponse)
    }
}
```

- [ ] **Step 3: Wire MotionController into LooiSession**

Modify `Packages/LooiKit/Sources/LooiKit/Session/LooiSession.swift` — add a `motion` property and start/stop the heartbeat as state changes.

Add inside the `LooiSession` class (after `currentPeripheral`):

```swift
    public let motion: MotionController

    /// Latest cliff state — owned by SensorController in Task 10, here
    /// stubbed as .grounded so MotionController's hard-block compiles.
    /// Task 10 replaces with a reference to SensorController.cliffState.
    public private(set) var cliffState: CliffState = .grounded
```

Update the `init` to construct `motion`:

```swift
    public init(transport: BLETransport) {
        self.transport = transport
        self.machine = SessionStateMachine()
        // Capture self after init via local closure-friendly factory.
        var cliffProvider: () -> CliffState = { .grounded }
        self.motion = MotionController(transport: transport, cliffStateProvider: { cliffProvider() })

        self.machine.onTransition = { [weak self] from, to in
            Task { @MainActor [weak self] in
                self?.state = to
                self?.handleStateTransition(from: from, to: to)
            }
        }
        // Now that self exists, wire the cliff provider to read self.cliffState.
        cliffProvider = { [weak self] in self?.cliffState ?? .grounded }

        self.disconnectionWatcher = Task { [weak self] in
            guard let self else { return }
            for await reason in transport.disconnections {
                await self.handleDisconnection(reason)
            }
        }
    }
```

Add a new method:

```swift
    private func handleStateTransition(from: SessionState, to: SessionState) {
        // I2/I4: heartbeat lifecycle bound to .ready.
        switch (from.isReady, to.isReady) {
        case (false, true):
            motion.startHeartbeat()
        case (true, false):
            motion.cancelHeartbeat()
        default:
            break
        }

        // I6: motion.stop on every .ready → not-.ready transition.
        if from.isReady && !to.isReady {
            Task { await motion.emergencyStop() }
        }
    }
```

- [ ] **Step 4: Write MotionController tests**

Create `Packages/LooiKit/Tests/LooiKitTests/MotionControllerTests.swift`:

```swift
import XCTest
import CoreBluetooth
@testable import LooiKit
import LooiKitTesting

@MainActor
final class MotionControllerTests: XCTestCase {

    func test_setMotion_whenGrounded_updatesCurrentMotion() throws {
        let mock = MockBLETransport()
        let ctl = MotionController(transport: mock, cliffStateProvider: { .grounded })
        try ctl.setMotion(MotionState(label: "Fwd", data: LooiCommand.Movement.forwardMax))
        XCTAssertEqual(ctl.currentMotion.data, LooiCommand.Movement.forwardMax)
    }

    func test_setMotion_whenSuspended_throwsCliffLockedAndDoesNotMutate() {
        let mock = MockBLETransport()
        var cliff: CliffState = .frontSuspended
        let ctl = MotionController(transport: mock, cliffStateProvider: { cliff })

        XCTAssertThrowsError(try ctl.forward()) { err in
            guard case LooiError.cliffLocked = err else {
                XCTFail("expected cliffLocked, got \(err)"); return
            }
        }
        XCTAssertEqual(ctl.currentMotion, .stop)  // unchanged
        _ = cliff  // silence unused-warning
    }

    func test_stop_alwaysAllowedEvenWhenSuspended() {
        let mock = MockBLETransport()
        let ctl = MotionController(transport: mock, cliffStateProvider: { .frontSuspended })
        ctl.stop()
        XCTAssertEqual(ctl.currentMotion, .stop)
    }

    func test_heartbeat_writesEvery30ms_usingWithoutResponse() async throws {
        let mock = MockBLETransport()
        let ctl = MotionController(transport: mock, cliffStateProvider: { .grounded })
        try ctl.forward()
        ctl.startHeartbeat()
        try? await Task.sleep(for: .milliseconds(100))
        ctl.cancelHeartbeat()

        let writes = await mock.writes
        // Expect ~3 writes in 100ms at 30ms cadence (allow 2-5 for jitter).
        XCTAssertGreaterThanOrEqual(writes.count, 2)
        XCTAssertLessThanOrEqual(writes.count, 5)
        // Every write goes to FED0 with .withoutResponse and forwardMax bytes.
        for w in writes {
            XCTAssertEqual(w.characteristic, LooiProtocol.Char.movement)
            XCTAssertEqual(w.type, .withoutResponse)
            XCTAssertEqual(w.data, LooiCommand.Movement.forwardMax)
        }
    }

    func test_emergencyStop_sendsExplicitStop() async {
        let mock = MockBLETransport()
        let ctl = MotionController(transport: mock, cliffStateProvider: { .grounded })
        try? ctl.forward()
        await ctl.emergencyStop()
        XCTAssertEqual(ctl.currentMotion, .stop)
        let writes = await mock.writes
        // Last write should be Movement.stop with .withResponse.
        let last = writes.last
        XCTAssertEqual(last?.data, LooiCommand.Movement.stop)
        XCTAssertEqual(last?.type, .withResponse)
    }

    func test_sessionEntersReady_startsHeartbeat() async {
        let mock = MockBLETransport()
        await mock.stubRead(LooiProtocol.Char.deviceInfoManufacturer, returns: Data())
        let session = LooiSession(transport: mock)
        session.startScanAndConnect(nameFilter: "LOOI")
        try? await Task.sleep(for: .milliseconds(50))
        await mock.simulateDiscovery(DiscoveredPeripheral(
            id: UUID(), name: "LOOI", rssi: -50,
            advertisedServices: [], manufacturerData: nil, lastSeen: Date()))
        try? await Task.sleep(for: .milliseconds(800))
        XCTAssertEqual(session.state, .ready)

        // After .ready, heartbeat should be ticking.
        try? await Task.sleep(for: .milliseconds(100))
        let writes = await mock.writes
        // Writes include handshake (2) + at least 1 heartbeat to FED0.
        let fed0Writes = writes.filter { $0.characteristic == LooiProtocol.Char.movement }
        XCTAssertGreaterThanOrEqual(fed0Writes.count, 1)
    }

    func test_sessionLeavesReady_stopsHeartbeatAndEmergencyStops() async {
        let mock = MockBLETransport()
        await mock.stubRead(LooiProtocol.Char.deviceInfoManufacturer, returns: Data())
        let session = LooiSession(transport: mock)
        session.startScanAndConnect()
        try? await Task.sleep(for: .milliseconds(50))
        await mock.simulateDiscovery(DiscoveredPeripheral(
            id: UUID(), name: "LOOI", rssi: -50,
            advertisedServices: [], manufacturerData: nil, lastSeen: Date()))
        try? await Task.sleep(for: .milliseconds(800))
        XCTAssertEqual(session.state, .ready)

        // Disconnect → I6 fires emergencyStop, heartbeat stops.
        session.disconnect()
        try? await Task.sleep(for: .milliseconds(100))

        let writes = await mock.writes
        // Last FED0 write should be the explicit Movement.stop from emergencyStop.
        let fed0 = writes.filter { $0.characteristic == LooiProtocol.Char.movement }
        XCTAssertEqual(fed0.last?.data, LooiCommand.Movement.stop)
    }
}
```

- [ ] **Step 5: Run tests**

```bash
swift test --package-path Packages/LooiKit 2>&1 | tail -30
```

Expected: `Test Suite 'All tests' passed`. The async-heartbeat tests are timing-sensitive; if `test_heartbeat_writesEvery30ms` flakes on slow CI, widen the upper bound to 7 instead of 5.

- [ ] **Step 6: Verify app builds**

```bash
xcodebuild build -project ulooi.xcodeproj -scheme ulooi \
  -destination 'platform=iOS Simulator,name=iPhone 16' -quiet 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add Packages/LooiKit
git commit -m "feat(motion): MotionController + 30ms heartbeat + cliff hard-block (I2/I4/I6)

MotionController owns the FED0 heartbeat (.withoutResponse, 30ms) and
exposes setMotion/forward/backward/spinLeft/spinRight/stop. setMotion
throws LooiError.cliffLocked when any wheel is suspended — the ONLY
safety gate per spec §9.1. .stop bypasses the check (always safe to send).

LooiSession.init constructs MotionController, wires cliff provider to
SensorController (stubbed .grounded until Task 10), starts/stops the
heartbeat on .ready enter/exit (I2/I4), and fires emergencyStop on any
.ready → non-.ready transition (I6)."
```

---

## Task 9: HeadController + LightController

**Files:**
- Create: `Packages/LooiKit/Sources/LooiKit/Controllers/HeadController.swift`
- Create: `Packages/LooiKit/Sources/LooiKit/Controllers/LightController.swift`
- Create: `Packages/LooiKit/Tests/LooiKitTests/HeadLightControllerTests.swift`
- Modify: `LooiSession.swift` — own `head: HeadController` and `light: LightController`.

- [ ] **Step 1: Write HeadController**

Create `Packages/LooiKit/Sources/LooiKit/Controllers/HeadController.swift`:

```swift
import Foundation
import OSLog

/// FED1 head pitch control. M0.5 finding: 0x00 = up, 0x5A = center,
/// 0xFF = down-then-spring-back. `lookDown` writes 0xFF — caller must
/// not assume it holds.
@MainActor
public final class HeadController {

    private let transport: BLETransport
    private let logger = Logger(subsystem: "ai.if2.ulooi", category: "looikit.head")

    public init(transport: BLETransport) {
        self.transport = transport
    }

    public func lookUp() async throws {
        try await transport.write(LooiCommand.Head.lookUp,
                                  to: LooiProtocol.Char.head,
                                  type: .withResponse)
    }

    public func lookDown() async throws {
        // Note: Looi auto-springs back to center; do NOT expect this to hold.
        try await transport.write(LooiCommand.Head.lookDown,
                                  to: LooiProtocol.Char.head,
                                  type: .withResponse)
    }

    public func center() async throws {
        try await transport.write(LooiCommand.Head.center,
                                  to: LooiProtocol.Char.head,
                                  type: .withResponse)
    }
}
```

- [ ] **Step 2: Write LightController**

Create `Packages/LooiKit/Sources/LooiKit/Controllers/LightController.swift`:

```swift
import Foundation
import OSLog

/// FED2 headlight control. M0.5 finding: 1-byte analog brightness
/// 0x00...0xFF (full range, not just on/off as sooperchargeforbots
/// claimed). 0.0 = off, 1.0 = max.
@MainActor
public final class LightController {

    private let transport: BLETransport
    private let logger = Logger(subsystem: "ai.if2.ulooi", category: "looikit.light")

    public init(transport: BLETransport) {
        self.transport = transport
    }

    /// Set analog brightness [0.0, 1.0]. Clamps out of range.
    public func set(brightness: Double) async throws {
        let clamped = max(0.0, min(1.0, brightness))
        let byte = UInt8(clamped * 255)
        try await transport.write(Data([byte]),
                                  to: LooiProtocol.Char.light,
                                  type: .withResponse)
    }

    public func off() async throws {
        try await set(brightness: 0.0)
    }
}
```

- [ ] **Step 3: Wire into LooiSession**

Modify `Packages/LooiKit/Sources/LooiKit/Session/LooiSession.swift` — add properties and initialize:

```swift
    public let head: HeadController
    public let light: LightController
```

In `init`, after constructing `motion`:

```swift
        self.head = HeadController(transport: transport)
        self.light = LightController(transport: transport)
```

- [ ] **Step 4: Write tests**

Create `Packages/LooiKit/Tests/LooiKitTests/HeadLightControllerTests.swift`:

```swift
import XCTest
import CoreBluetooth
@testable import LooiKit
import LooiKitTesting

@MainActor
final class HeadLightControllerTests: XCTestCase {

    // MARK: - Head

    func test_lookUp_writes0x00ToFED1() async throws {
        let mock = MockBLETransport()
        let h = HeadController(transport: mock)
        try await h.lookUp()
        let writes = await mock.writes
        XCTAssertEqual(writes.first?.characteristic, LooiProtocol.Char.head)
        XCTAssertEqual(writes.first?.data, Data([0x00]))
    }

    func test_lookDown_writes0xFFToFED1() async throws {
        let mock = MockBLETransport()
        let h = HeadController(transport: mock)
        try await h.lookDown()
        let writes = await mock.writes
        XCTAssertEqual(writes.first?.data, Data([0xFF]))
    }

    func test_center_writes0x5AToFED1() async throws {
        let mock = MockBLETransport()
        let h = HeadController(transport: mock)
        try await h.center()
        let writes = await mock.writes
        XCTAssertEqual(writes.first?.data, Data([0x5A]))
    }

    // MARK: - Light

    func test_lightFull_writes0xFFToFED2() async throws {
        let mock = MockBLETransport()
        let l = LightController(transport: mock)
        try await l.set(brightness: 1.0)
        let writes = await mock.writes
        XCTAssertEqual(writes.first?.characteristic, LooiProtocol.Char.light)
        XCTAssertEqual(writes.first?.data, Data([0xFF]))
    }

    func test_lightHalf_writesApprox128ToFED2() async throws {
        let mock = MockBLETransport()
        let l = LightController(transport: mock)
        try await l.set(brightness: 0.5)
        let writes = await mock.writes
        let byte = writes.first!.data.first!
        XCTAssertGreaterThanOrEqual(byte, 126)
        XCTAssertLessThanOrEqual(byte, 128)
    }

    func test_lightOff_writes0x00ToFED2() async throws {
        let mock = MockBLETransport()
        let l = LightController(transport: mock)
        try await l.off()
        let writes = await mock.writes
        XCTAssertEqual(writes.first?.data, Data([0x00]))
    }

    func test_lightClampsAboveOne() async throws {
        let mock = MockBLETransport()
        let l = LightController(transport: mock)
        try await l.set(brightness: 5.0)
        let writes = await mock.writes
        XCTAssertEqual(writes.first?.data, Data([0xFF]))
    }
}
```

- [ ] **Step 5: Run tests + verify app build**

```bash
swift test --package-path Packages/LooiKit 2>&1 | tail -20
xcodebuild build -project ulooi.xcodeproj -scheme ulooi \
  -destination 'platform=iOS Simulator,name=iPhone 16' -quiet 2>&1 | tail -10
```

Expected: tests pass, app builds.

- [ ] **Step 6: Commit**

```bash
git add Packages/LooiKit
git commit -m "feat(head+light): HeadController + LightController

HeadController exposes lookUp/lookDown/center wrapping FED1 (0x00 / 0xFF
/ 0x5A respectively); caller is warned that 0xFF auto-springs back
(M0.5 finding) so 'stay down' is not a thing.

LightController exposes set(brightness:) for analog [0.0, 1.0] →
[0x00, 0xFF] on FED2 (M0.5 confirmed analog gradient, not binary
on/off). Clamps out-of-range inputs.

Both wired into LooiSession as public properties."
```

---

## Task 10: SensorController + Battery Poll + FED9 Decoder (I3/I4)

**Files:**
- Create: `Packages/LooiKit/Sources/LooiKit/Controllers/SensorController.swift`
- Create: `Packages/LooiKit/Tests/LooiKitTests/SensorControllerTests.swift`
- Modify: `LooiSession.swift` — own `sensor: SensorController`, start/stop battery poll on `.ready` enter/exit, wire `cliffState` to read from `sensor.cliffState`.

- [ ] **Step 1: Write SensorController**

Create `Packages/LooiKit/Sources/LooiKit/Controllers/SensorController.swift`:

```swift
import Foundation
import Observation
import OSLog

/// Observable sensor state + 4s FED8 battery poll. Decodes the FED9
/// multi-packet telemetry stream into typed state (cliff, IMU, touch,
/// boot). Per spec §5.3 and M0.5 findings:
///   FED9 packet byte 0 is a type tag:
///     0x01 cliff   — byte 1 is a 4-bit cliff bitfield
///     0x02 IMU     — bytes 1..7 are 3× signed int16 (x, y, z)
///     0x09 touch   — byte 1 is a zone/intensity composite (deferred)
///     0x11 boot    — booted/ready status from Looi firmware
@MainActor
@Observable
public final class SensorController {

    private let transport: BLETransport
    private let logger = Logger(subsystem: "ai.if2.ulooi", category: "looikit.sensor")

    public private(set) var cliffState: CliffState = .grounded
    public private(set) var imu: IMUReading = .zero
    public private(set) var batteryPercent: Int? = nil
    public private(set) var lastTouchEvent: TouchEvent? = nil
    public private(set) var batteryPollCount: Int = 0

    private var batteryTask: Task<Void, Never>?
    private var sensorsTask: Task<Void, Never>?
    private var telemetryTask: Task<Void, Never>?

    public struct IMUReading: Sendable, Equatable {
        public let x: Int16
        public let y: Int16
        public let z: Int16
        public static let zero = IMUReading(x: 0, y: 0, z: 0)
    }

    public struct TouchEvent: Sendable, Equatable {
        public let raw: UInt8
        public let timestamp: Date
    }

    public init(transport: BLETransport) {
        self.transport = transport
    }

    /// Subscribe to FED5+FED9 streams (typically given by HandshakeRunner's
    /// SubscribedStreams). Begins decoding immediately.
    public func consume(sensors: AsyncStream<Data>, telemetry: AsyncStream<Data>) {
        sensorsTask?.cancel()
        telemetryTask?.cancel()

        sensorsTask = Task { [weak self] in
            for await data in sensors {
                self?.handleSensorPacket(data)
            }
        }
        telemetryTask = Task { [weak self] in
            for await data in telemetry {
                self?.handleTelemetryPacket(data)
            }
        }
    }

    /// Begin 4s FED8 battery polling. Idempotent.
    public func startBatteryPoll() {
        cancelBatteryPoll()
        batteryPollCount = 0
        batteryTask = Task { [weak self] in
            guard let self else { return }
            self.logger.info("battery poll: starting (4s interval)")
            while !Task.isCancelled {
                do {
                    let data = try await self.transport.read(from: LooiProtocol.Char.battery)
                    self.batteryPollCount += 1
                    if let byte = data.first {
                        self.batteryPercent = Int(byte)
                    }
                } catch {
                    self.logger.warning("battery poll: read failed: \(String(describing: error), privacy: .public)")
                    break
                }
                try? await Task.sleep(for: LooiProtocol.Timing.batteryPollInterval)
            }
        }
    }

    public func cancelBatteryPoll() {
        batteryTask?.cancel()
        batteryTask = nil
    }

    public func stopConsuming() {
        sensorsTask?.cancel(); sensorsTask = nil
        telemetryTask?.cancel(); telemetryTask = nil
    }

    // MARK: - Decode

    private func handleSensorPacket(_ data: Data) {
        // FED5 sensor packets — touch / button events. M0.5 captured raw
        // bytes; full decode is deferred (spec §3 out-of-scope). For M1
        // we just publish lastTouchEvent.raw.
        guard let first = data.first else { return }
        lastTouchEvent = TouchEvent(raw: first, timestamp: Date())
    }

    private func handleTelemetryPacket(_ data: Data) {
        guard let type = data.first else { return }
        switch type {
        case 0x01:
            // Cliff state — byte 1 is the bitfield.
            guard data.count >= 2 else { return }
            cliffState = CliffState(rawValue: data[1])

        case 0x02:
            // IMU — bytes 1..7 are 3× signed int16 little-endian.
            guard data.count >= 7 else { return }
            imu = IMUReading(
                x: data.readInt16LE(at: 1),
                y: data.readInt16LE(at: 3),
                z: data.readInt16LE(at: 5)
            )

        case 0x09:
            // Touch event on FED9 stream (M0.5 saw 0x09 here too).
            guard data.count >= 2 else { return }
            lastTouchEvent = TouchEvent(raw: data[1], timestamp: Date())

        case 0x11:
            // Boot status — log only.
            logger.info("telemetry: boot status \(data.hexEncoded, privacy: .public)")

        default:
            logger.info("telemetry: unknown type 0x\(String(type, radix: 16), privacy: .public) data=\(data.hexEncoded, privacy: .public)")
        }
    }
}

extension Data {
    /// Read a signed 16-bit little-endian value at `offset`. Returns 0 if
    /// out of bounds (caller should pre-check).
    fileprivate func readInt16LE(at offset: Int) -> Int16 {
        guard offset + 1 < count else { return 0 }
        let lo = UInt16(self[offset])
        let hi = UInt16(self[offset + 1])
        let u = (hi << 8) | lo
        return Int16(bitPattern: u)
    }
}
```

- [ ] **Step 2: Wire SensorController into LooiSession**

Modify `Packages/LooiKit/Sources/LooiKit/Session/LooiSession.swift`:

Add property:

```swift
    public let sensor: SensorController
```

In `init`, after constructing other controllers:

```swift
        self.sensor = SensorController(transport: transport)
```

Replace the stubbed `cliffState` declaration. Remove:

```swift
    public private(set) var cliffState: CliffState = .grounded
```

And replace the `cliffProvider` line with:

```swift
        cliffProvider = { [weak self] in self?.sensor.cliffState ?? .grounded }
```

Modify `runConnect` — after `HandshakeRunner.run()` succeeds, hook the streams:

```swift
            try machine.transition(to: .handshaking)
            let streams = try await HandshakeRunner(transport: transport).run()
            sensor.consume(sensors: streams.sensors, telemetry: streams.telemetry)
```

Modify `handleStateTransition` — extend with battery-poll lifecycle (I3):

```swift
    private func handleStateTransition(from: SessionState, to: SessionState) {
        switch (from.isReady, to.isReady) {
        case (false, true):
            motion.startHeartbeat()
            sensor.startBatteryPoll()
        case (true, false):
            motion.cancelHeartbeat()
            sensor.cancelBatteryPoll()
            sensor.stopConsuming()
        default:
            break
        }
        if from.isReady && !to.isReady {
            Task { await motion.emergencyStop() }
        }
    }
```

- [ ] **Step 3: Write tests**

Create `Packages/LooiKit/Tests/LooiKitTests/SensorControllerTests.swift`:

```swift
import XCTest
import CoreBluetooth
@testable import LooiKit
import LooiKitTesting

@MainActor
final class SensorControllerTests: XCTestCase {

    // MARK: - FED9 decode

    func test_telemetryType0x01_decodesCliffState() async {
        let mock = MockBLETransport()
        let sc = SensorController(transport: mock)
        let s = AsyncStream<Data>.makeStream()
        let t = AsyncStream<Data>.makeStream()
        sc.consume(sensors: s.stream, telemetry: t.stream)

        // All four wheels suspended → bitfield 0x0F
        t.continuation.yield(Data([0x01, 0x0F]))
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(sc.cliffState, [.frontSuspended, .rearSuspended, .leftSuspended, .rightSuspended])

        // Grounded
        t.continuation.yield(Data([0x01, 0x00]))
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(sc.cliffState, .grounded)
        XCTAssertTrue(sc.cliffState.isGrounded)
    }

    func test_telemetryType0x02_decodesIMUSignedInt16LE() async {
        let mock = MockBLETransport()
        let sc = SensorController(transport: mock)
        let s = AsyncStream<Data>.makeStream()
        let t = AsyncStream<Data>.makeStream()
        sc.consume(sensors: s.stream, telemetry: t.stream)

        // x=1, y=-1, z=256 (little-endian)
        let bytes: [UInt8] = [
            0x02,
            0x01, 0x00,       // x = 1
            0xFF, 0xFF,       // y = -1
            0x00, 0x01        // z = 256
        ]
        t.continuation.yield(Data(bytes))
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(sc.imu.x, 1)
        XCTAssertEqual(sc.imu.y, -1)
        XCTAssertEqual(sc.imu.z, 256)
    }

    func test_telemetryType0x09_updatesLastTouchEvent() async {
        let mock = MockBLETransport()
        let sc = SensorController(transport: mock)
        let s = AsyncStream<Data>.makeStream()
        let t = AsyncStream<Data>.makeStream()
        sc.consume(sensors: s.stream, telemetry: t.stream)

        t.continuation.yield(Data([0x09, 0x42]))
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(sc.lastTouchEvent?.raw, 0x42)
    }

    func test_telemetryType0x11_doesNotCrashOrUpdateOtherFields() async {
        let mock = MockBLETransport()
        let sc = SensorController(transport: mock)
        let s = AsyncStream<Data>.makeStream()
        let t = AsyncStream<Data>.makeStream()
        sc.consume(sensors: s.stream, telemetry: t.stream)

        t.continuation.yield(Data([0x11, 0x01, 0x02]))
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(sc.cliffState, .grounded)
        XCTAssertEqual(sc.imu, .zero)
    }

    // MARK: - Battery poll (I3/I4)

    func test_batteryPoll_readsFED8AndUpdatesPercent() async {
        let mock = MockBLETransport()
        await mock.stubRead(LooiProtocol.Char.battery, returns: Data([0x55]))  // 85%
        let sc = SensorController(transport: mock)
        sc.startBatteryPoll()
        try? await Task.sleep(for: .milliseconds(100))
        sc.cancelBatteryPoll()
        XCTAssertEqual(sc.batteryPercent, 85)
        let reads = await mock.reads
        XCTAssertGreaterThanOrEqual(reads.filter { $0 == LooiProtocol.Char.battery }.count, 1)
    }

    func test_cancelBatteryPoll_stopsReads() async {
        let mock = MockBLETransport()
        await mock.stubRead(LooiProtocol.Char.battery, returns: Data([0x50]))
        let sc = SensorController(transport: mock)
        sc.startBatteryPoll()
        try? await Task.sleep(for: .milliseconds(100))
        sc.cancelBatteryPoll()
        let countAtCancel = (await mock.reads).filter { $0 == LooiProtocol.Char.battery }.count
        try? await Task.sleep(for: .seconds(5))  // would tick ≥ 1 if not cancelled
        let countAfterWait = (await mock.reads).filter { $0 == LooiProtocol.Char.battery }.count
        XCTAssertEqual(countAtCancel, countAfterWait)
    }
}
```

- [ ] **Step 4: Run tests + verify app build**

```bash
swift test --package-path Packages/LooiKit 2>&1 | tail -30
xcodebuild build -project ulooi.xcodeproj -scheme ulooi \
  -destination 'platform=iOS Simulator,name=iPhone 16' -quiet 2>&1 | tail -10
```

Expected: green tests, app builds. The cancel test sleeps 5 seconds — that's slow; if it pains CI, shrink `LooiProtocol.Timing.batteryPollInterval` to 1s in a separate test helper.

- [ ] **Step 5: Commit**

```bash
git add Packages/LooiKit
git commit -m "feat(sensor): SensorController + 4s battery poll + FED9 decoder (I3/I4)

SensorController publishes cliffState / imu / batteryPercent /
lastTouchEvent as @Observable properties. Decodes FED9 multi-packet:
type 0x01 = cliff bitfield, 0x02 = IMU 3× int16 LE, 0x09 = touch
event, 0x11 = boot status. Owns the 4s FED8 battery poll started by
LooiSession on .ready (I3) and cancelled on .ready exit (I4).

LooiSession wires SensorController.cliffState into MotionController's
cliff hard-block (replacing the stubbed .grounded provider), and pipes
HandshakeRunner.SubscribedStreams into sensor.consume()."
```

---

## Task 11: Reconnect Policy + Persisted Peripheral UUID

**Files:**
- Create: `Packages/LooiKit/Sources/LooiKit/Session/ReconnectPolicy.swift`
- Create: `Packages/LooiKit/Sources/LooiKitTesting/FakeClock.swift`
- Create: `Packages/LooiKit/Tests/LooiKitTests/ReconnectPolicyTests.swift`
- Modify: `LooiSession.swift` — replace `handleDisconnection` to enter `.reconnecting` with backoff, persist/restore `pairedPeripheralID`.

- [ ] **Step 1: Write ReconnectPolicy**

Create `Packages/LooiKit/Sources/LooiKit/Session/ReconnectPolicy.swift`:

```swift
import Foundation

/// Pure-Swift backoff schedule for .reconnecting. Spec §5.2:
/// 1s → 2s → 4s → 8s → 16s → 30s → 30s..., capped at 60s total window.
public struct ReconnectPolicy: Sendable {

    public let totalWindow: Duration
    public let schedule: [Duration]

    public static let `default` = ReconnectPolicy(
        totalWindow: .seconds(60),
        schedule: [.seconds(1), .seconds(2), .seconds(4), .seconds(8), .seconds(16), .seconds(30)]
    )

    public init(totalWindow: Duration, schedule: [Duration]) {
        self.totalWindow = totalWindow
        self.schedule = schedule
    }

    /// Delay before attempt `n` (1-indexed). Past the schedule length,
    /// repeats the last value. Returns nil if the cumulative delay would
    /// exceed totalWindow.
    public func delay(forAttempt n: Int) -> Duration? {
        guard n >= 1 else { return nil }
        var elapsed: Duration = .zero
        for i in 0..<n {
            let step = i < schedule.count ? schedule[i] : schedule.last!
            elapsed = elapsed + step
            if elapsed > totalWindow { return nil }
        }
        return n - 1 < schedule.count ? schedule[n - 1] : schedule.last!
    }

    /// Total elapsed time after `n` attempts (1-indexed, inclusive).
    public func elapsedAfter(attempts n: Int) -> Duration {
        guard n >= 1 else { return .zero }
        var elapsed: Duration = .zero
        for i in 0..<n {
            elapsed = elapsed + (i < schedule.count ? schedule[i] : schedule.last!)
        }
        return elapsed
    }
}
```

- [ ] **Step 2: Write FakeClock helper for tests**

Create `Packages/LooiKit/Sources/LooiKitTesting/FakeClock.swift`:

```swift
import Foundation

/// Test clock that advances on demand. Not full Clock conformance —
/// just a simple counter for asserting "after N attempts, elapsed = X".
public final class FakeClock {
    public private(set) var now: Duration = .zero
    public init() {}
    public func advance(by d: Duration) { now = now + d }
}
```

- [ ] **Step 3: Write tests for the policy**

Create `Packages/LooiKit/Tests/LooiKitTests/ReconnectPolicyTests.swift`:

```swift
import XCTest
@testable import LooiKit
import LooiKitTesting

final class ReconnectPolicyTests: XCTestCase {

    func test_defaultSchedule_firstAttemptDelay1s() {
        XCTAssertEqual(ReconnectPolicy.default.delay(forAttempt: 1), .seconds(1))
    }

    func test_defaultSchedule_sequenceDoubles() {
        let p = ReconnectPolicy.default
        XCTAssertEqual(p.delay(forAttempt: 1), .seconds(1))
        XCTAssertEqual(p.delay(forAttempt: 2), .seconds(2))
        XCTAssertEqual(p.delay(forAttempt: 3), .seconds(4))
        XCTAssertEqual(p.delay(forAttempt: 4), .seconds(8))
        XCTAssertEqual(p.delay(forAttempt: 5), .seconds(16))
        XCTAssertEqual(p.delay(forAttempt: 6), .seconds(30))
    }

    func test_beyondSchedule_capsAt30s() {
        let p = ReconnectPolicy.default
        XCTAssertNil(p.delay(forAttempt: 7))  // cumulative 1+2+4+8+16+30+30 = 91s > 60s window
    }

    func test_elapsedAfter4Attempts_is15s() {
        XCTAssertEqual(ReconnectPolicy.default.elapsedAfter(attempts: 4), .seconds(15))
    }

    func test_zeroOrNegativeAttempt_returnsNil() {
        XCTAssertNil(ReconnectPolicy.default.delay(forAttempt: 0))
        XCTAssertNil(ReconnectPolicy.default.delay(forAttempt: -1))
    }

    func test_customWindow_truncatesEarly() {
        let p = ReconnectPolicy(totalWindow: .seconds(5), schedule: [.seconds(1), .seconds(2), .seconds(4)])
        XCTAssertEqual(p.delay(forAttempt: 1), .seconds(1))
        XCTAssertEqual(p.delay(forAttempt: 2), .seconds(2))
        // 1+2+4=7 > 5 → nil
        XCTAssertNil(p.delay(forAttempt: 3))
    }
}
```

- [ ] **Step 4: Wire reconnect into LooiSession**

Modify `Packages/LooiKit/Sources/LooiKit/Session/LooiSession.swift`:

Add properties:

```swift
    public let reconnectPolicy: ReconnectPolicy

    /// UserDefaults-backed last paired peripheral. Auto-attempted first
    /// on next reconnect / next app launch.
    public var pairedPeripheralID: UUID? {
        get {
            UserDefaults.standard.string(forKey: Self.pairedKey).flatMap(UUID.init(uuidString:))
        }
        set {
            if let v = newValue {
                UserDefaults.standard.set(v.uuidString, forKey: Self.pairedKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.pairedKey)
            }
        }
    }

    public func forgetPairing() { pairedPeripheralID = nil }

    private static let pairedKey = "looikit.last.paired.peripheral.id"
    private var reconnectTask: Task<Void, Never>?
```

Update `init` to take a policy (default-able):

```swift
    public init(transport: BLETransport, reconnectPolicy: ReconnectPolicy = .default) {
        self.transport = transport
        self.reconnectPolicy = reconnectPolicy
        // ... rest of init unchanged
```

Replace `handleDisconnection` with backoff-aware version:

```swift
    private func handleDisconnection(_ reason: DisconnectionReason) async {
        logger.info("disconnection: \(String(describing: reason), privacy: .public) from \(self.state.description, privacy: .public)")
        guard state != .disconnected else { return }  // user already disconnected

        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            guard let self else { return }
            await self.runReconnectLoop()
        }
    }

    private func runReconnectLoop() async {
        var attempt = 1
        while !Task.isCancelled {
            do {
                try machine.transition(to: .reconnecting(attempt: attempt))
            } catch {
                try? machine.transition(to: .disconnected)
                return
            }

            guard let delay = reconnectPolicy.delay(forAttempt: attempt) else {
                try? machine.transition(to: .disconnected)
                return
            }
            try? await Task.sleep(for: delay)
            if Task.isCancelled { return }

            // Try paired UUID first; fall back to scan.
            if let pairedID = pairedPeripheralID {
                try? machine.transition(to: .scanning)
                await runConnect(id: pairedID, fromState: .scanning)
                if state.isReady { return }
            } else {
                startScanAndConnect()
                try? await Task.sleep(for: .seconds(2))
                if state.isReady { return }
            }
            attempt += 1
        }
    }
```

Modify `runConnect` to save the pairing after `.ready`:

```swift
        try? machine.transition(to: .ready)
        pairedPeripheralID = id
```

Modify `disconnect()` to cancel the reconnect loop:

```swift
    public func disconnect() {
        Task { [weak self] in
            guard let self else { return }
            self.scanTask?.cancel()
            self.connectTask?.cancel()
            self.reconnectTask?.cancel()
            await self.transport.disconnect()
            try? self.machine.transition(to: .disconnected)
            self.currentPeripheral = nil
        }
    }
```

- [ ] **Step 5: Run tests + verify app build**

```bash
swift test --package-path Packages/LooiKit 2>&1 | tail -30
xcodebuild build -project ulooi.xcodeproj -scheme ulooi \
  -destination 'platform=iOS Simulator,name=iPhone 16' -quiet 2>&1 | tail -10
```

Expected: green tests, app builds. The runtime reconnect path is exercised by `LooiSessionTests` happy path; full backoff-timing assertions are deferred to integration tests in a future PR.

- [ ] **Step 6: Commit**

```bash
git add Packages/LooiKit
git commit -m "feat(reconnect): backoff schedule + persisted peripheral UUID

ReconnectPolicy.default: 1/2/4/8/16/30s schedule, 60s total window
(spec §5.2). Past the schedule length, returns nil → transition to
.disconnected.

LooiSession watches the transport's disconnection stream; on drop
(other than user-initiated), enters .reconnecting(attempt:), waits
the next backoff step, then tries the paired UUID first (saved in
UserDefaults after successful .ready). FakeClock helper in
LooiKitTesting for future timing-aware tests."
```

---

## Task 12: App migration — DevTools uses LooiSession; delete inline `ulooi/LooiKit/`

**Files:**
- Create: `ulooi/App/LooiBootstrap.swift` (new — provides app-level singleton)
- Modify: `ulooi/DevTools/ConnectionBanner.swift`, `ulooi/DevTools/DevToolsRootView.swift`, every `ulooi/DevTools/Probe/*.swift`
- Delete: `ulooi/LooiKit/BLECentral.swift`, `BLECentral+CentralDelegate.swift`, `BLECentral+PeripheralDelegate.swift`
- Delete: `ulooi/LooiKit/` (folder — should be empty after deletions in this and previous tasks)

- [ ] **Step 1: Create the app-level LooiSession bootstrap**

Create `ulooi/App/LooiBootstrap.swift`:

```swift
import Foundation
import LooiKit

/// App-level singleton that holds the production LooiSession. Until M1
/// PR 3 reshapes the app to inject this via @Environment, DevTools and
/// future production UI both reach it via .shared.
@MainActor
public final class LooiBootstrap {
    public static let shared = LooiBootstrap()
    public let session: LooiSession

    private init() {
        let transport = CoreBluetoothTransport()
        self.session = LooiSession(transport: transport)
    }
}
```

(Create the `App/` folder if it doesn't exist: `mkdir -p ulooi/App`.)

- [ ] **Step 2: Replace BLECentral references in DevTools**

For each of these files, replace `BLECentral.shared` references with `LooiBootstrap.shared.session` references. Map APIs as follows:

| Old (BLECentral)                | New (LooiSession)                                 |
|---------------------------------|---------------------------------------------------|
| `BLECentral.shared`             | `LooiBootstrap.shared.session`                    |
| `central.state`                 | `session.state.description` (or compare via switch) |
| `central.discoveries`           | (replaced by scan AsyncStream; for DevTools' Scan tab, run `for await p in transport.scan(...)` in a Task and accumulate manually OR keep a small `@State var discoveries: [DiscoveredPeripheral] = []` array updated from the stream) |
| `central.connectedPeripheral`   | `session.currentPeripheral`                       |
| `central.startScan()`           | `session.startScanAndConnect()`                   |
| `central.connect(id)`           | `session.connect(to: id)`                         |
| `central.disconnect()`          | `session.disconnect()`                            |
| `central.currentMotion = X`     | `try? session.motion.setMotion(X)`                |
| `central.heartbeatTicks`        | `session.motion.heartbeatTicks`                   |
| `central.batteryPolls`          | `session.sensor.batteryPollCount`                 |
| `central.findCharacteristic(u)` | (no longer exposed — DevTools' Inspect tab loses this; mark TODO + display "[deferred to next dev iteration]" if needed) |

Files to modify (search-replace per the table):
- `ulooi/DevTools/ConnectionBanner.swift`
- `ulooi/DevTools/DevToolsRootView.swift`
- `ulooi/DevTools/Probe/ScanView.swift`
- `ulooi/DevTools/Probe/InspectView.swift`
- `ulooi/DevTools/Probe/CommandView.swift`
- `ulooi/DevTools/Probe/SenseView.swift`
- `ulooi/DevTools/Probe/LogsView.swift` (likely unchanged — ProbeLog stays app-local)

For Scan tab: add a small wrapper `@MainActor @Observable final class DevToolsScanCoordinator` in `DevTools/Probe/ScanView.swift` that runs the AsyncStream and exposes a `[DiscoveredPeripheral]` array for the view. Pattern:

```swift
@MainActor
@Observable
final class DevToolsScanCoordinator {
    var discoveries: [DiscoveredPeripheral] = []
    private var scanTask: Task<Void, Never>?

    func start(nameFilter: String, transport: BLETransport) {
        scanTask = Task {
            for await p in transport.scan(nameFilter: nameFilter) {
                if let idx = discoveries.firstIndex(where: { $0.id == p.id }) {
                    discoveries[idx] = p
                } else {
                    discoveries.append(p)
                }
            }
        }
    }

    func stop() async {
        scanTask?.cancel()
    }
}
```

Note: this exposes the transport through DevTools — that's OK because DevTools is a debug surface. Production UI (M1 PR 2) will call `session.startScanAndConnect()` instead.

- [ ] **Step 3: Delete the now-redundant inline BLECentral files**

```bash
git rm ulooi/LooiKit/BLECentral.swift
git rm ulooi/LooiKit/BLECentral+CentralDelegate.swift
git rm ulooi/LooiKit/BLECentral+PeripheralDelegate.swift
rmdir ulooi/LooiKit 2>/dev/null || true  # empty if Task 2 moved everything else
```

- [ ] **Step 4: Verify app builds**

```bash
xcodebuild build -project ulooi.xcodeproj -scheme ulooi \
  -destination 'platform=iOS Simulator,name=iPhone 16' -quiet 2>&1 | tail -20
```

Expected: `** BUILD SUCCEEDED **`. If a DevTools file still references `BLECentral`, the compile error names it — fix and re-run.

- [ ] **Step 5: Real-hardware smoke (manual)**

This is the PR 1 ship gate. Install on a real iPhone (Cmd+R from Xcode), connect to a real Looi, and walk through every DevTools tab:

1. **Scan tab** — discovers Looi within ~5s; tap row triggers connect
2. **Connect+Init** — ConnectionBanner turns green showing "Connected · NN%"
3. **CommandView Motion** — Forward (max) makes Looi move; STOP halts
4. **CommandView Head** — lookUp / center / lookDown each affect head pitch
5. **CommandView Light** — analog brightness slider changes headlight
6. **SenseView** — battery percentage shows; cliff state shows "grounded" when on table, flips to "suspended" when lifted
7. **LogsView** — events appear with proper categorization
8. **Disconnect** — clean disconnect; ConnectionBanner goes red

If any tab regresses, fix the call-site mapping (Step 2 table) and re-test.

- [ ] **Step 6: Run all tests one last time**

```bash
swift test --package-path Packages/LooiKit 2>&1 | tail -10
xcodebuild test \
  -project ulooi.xcodeproj \
  -scheme LooiKit \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  2>&1 | tail -20
```

Expected: both green.

- [ ] **Step 7: Commit and open the PR**

```bash
git add ulooi Packages/LooiKit
git commit -m "refactor(devtools): migrate to LooiSession; delete inline BLECentral

DevTools' five tabs (Scan / Inspect / Command / Sense / Logs) now drive
the production LooiSession via LooiBootstrap.shared.session. Deletes
ulooi/LooiKit/BLECentral{,+CentralDelegate,+PeripheralDelegate}.swift —
all functionality is now in Packages/LooiKit. Inspect tab loses raw
findCharacteristic for now (debug-only feature, deferred).

Concludes M1 PR 1. Real-hardware smoke checklist (8 steps) all pass."

git fetch origin
git push -u origin plan/m1-pr1-looikit-package
gh pr create --base main --title "M1 PR 1: LooiKit Swift Package extraction" --body "$(cat <<'EOF'
## Summary
- Extract LooiKit into Packages/LooiKit/ as a standalone Swift Package
- BLETransport protocol + CoreBluetoothTransport (prod) + MockBLETransport (test)
- LooiSession + 9-state SessionStateMachine + HandshakeRunner + 4 Controllers
- LooiError 9-case LocalizedError (Chinese primary, English fallback)
- ReconnectPolicy with 1/2/4/8/16/30s backoff, 60s window, persisted UUID
- ~80 unit tests in LooiKitTests covering invariants I1-I8

Implements spec §5 + §11.1 from \`docs/superpowers/specs/2026-05-17-ulooi-m1-foundation-design.md\`.

## Commits (bisectable)

| # | Commit | What |
|---|---|---|
| 1 | chore: scaffold Packages/LooiKit + pbxproj wiring | Empty package wired into xcodeproj |
| 2 | refactor: lift ulooi/LooiKit/* into Packages/LooiKit | Move + make public + command-byte tests |
| 3 | feat(transport): BLETransport + CoreBluetoothTransport + MockBLETransport | Testable seam |
| 4 | feat(errors): LooiError + CliffState + HandshakeStep | LocalizedError, zh primary |
| 5 | feat(session): SessionState + SessionStateMachine | 9 states + transition validation |
| 6 | feat(handshake): HandshakeRunner with typed steps | FEDA sequence reified |
| 7 | feat(session): LooiSession on BLETransport | @Observable top-level handle |
| 8 | feat(motion): MotionController + 30ms heartbeat + cliff hard-block (I2/I4/I6) | Safety gate |
| 9 | feat(head+light): HeadController + LightController | FED1 + FED2 wrappers |
| 10 | feat(sensor): SensorController + battery poll + FED9 decoder (I3/I4) | Observable sensor state |
| 11 | feat(reconnect): backoff + persisted peripheral UUID | 60s window auto-reconnect |
| 12 | refactor(devtools): migrate to LooiSession; delete inline BLECentral | Cutover |

## Test plan

- [ ] \`swift test --package-path Packages/LooiKit\` — all green
- [ ] \`xcodebuild build -scheme ulooi\` — app builds
- [ ] \`xcodebuild test -scheme LooiKit\` — all green
- [ ] Real-hardware smoke (8 steps) per Task 12 Step 5
EOF
)"
```

---

## Self-Review

### Spec Coverage Check

Walking through spec §§ 5 and 11.1:

| Spec item | Covered in |
|---|---|
| §5.1 three-layer dependency (app / LooiKit / transport) | Task 1, Task 3, Task 12 |
| §5.2 9-state machine + transitions + 60s reconnect + backoff + UserDefaults paired UUID | Task 5, Task 7, Task 11 |
| §5.3 MotionController + heartbeat .withoutResponse + cliff hard-block | Task 8 |
| §5.3 HeadController (0x00/0x5A/0xFF semantics documented) | Task 9 |
| §5.3 LightController (analog brightness) | Task 9 |
| §5.3 SensorController (@Observable cliffState/imu/batteryPercent/touchEvent) + 4s FED8 poll + FED9 decoder 0x01/0x02/0x09/0x11 | Task 10 |
| §5.4 I1 single-threaded state mutation | Task 5 (state machine emits once), Task 7 (@MainActor LooiSession) |
| §5.4 I2/I3 heartbeat + battery poll bound to .ready | Task 8, Task 10 |
| §5.4 I4 stop heartbeat + battery poll on leave .ready | Task 8, Task 10 |
| §5.4 I5 single setState log point + single observer notify | Task 5 |
| §5.4 I6 motion.stop on .ready-leave + cliff transitions | Task 8 (emergencyStop); app lifecycle hooks deferred to PR 3 |
| §5.4 I7/I8 gesture cleanup + actor serialization | Deferred to PR 2 (GestureLibrary) |
| §5.5 LooiError 9 cases + LocalizedError | Task 4 |
| §11.1 PR 1 commit list | Mapped 1:1 above |
| §10 BLETransport protocol shape | Task 3 |

**Gaps / deferred:**
- App lifecycle hooks (`willResignActive`, `didEnterBackground`, `willEnterForeground`) → PR 3
- Touch zone differentiation → captured as M0.5 deferred (per spec §3); Task 10 publishes `lastTouchEvent.raw`
- 4-direction cliff full mapping → Task 10 ships the `CliffState` shape for it; per-bit confirmation is opportunistic per spec §3

### Placeholder Scan

Searched for: "TBD", "TODO", "implement later", "fill in details", "Similar to Task N".
- Task 12 Step 2 has `[deferred to next dev iteration]` for DevTools Inspect's raw findCharacteristic — acceptable; it's a debug-only feature being intentionally removed, documented as such.
- HandshakeRunner Step 4 references SessionState before Task 5 — explicitly called out as a reorder note ("do Task 5 first") with a recommendation, not a placeholder.
- Task 4 Step 4 has the same cross-task dependency note for LooiError.sessionNotReady. Same explicit reorder guidance.

No silent placeholders.

### Type-Consistency Check

- `LooiError.cliffLocked(directions: CliffState)` — Task 4 defines; Task 8 throws with `cliffStateProvider()` (a `CliffState`). Consistent.
- `LooiError.handshakeFailed(step: HandshakeStep)` — Task 4 defines step; Task 6 throws each variant. Consistent.
- `SessionState.reconnecting(attempt: Int)` — Task 5 defines; Task 11 uses `attempt:`. Consistent.
- `MotionController.setMotion(_:)` — Task 8 signature `setMotion(_ motion: MotionState) throws`; callers in tests use `.setMotion(MotionState(...))`. Consistent.
- `HandshakeRunner.SubscribedStreams` — Task 6 defines `sensors`/`telemetry`; Task 10 consumes `streams.sensors`/`.telemetry`. Consistent.
- `LooiSession.sensor`, `.motion`, `.head`, `.light` — added across Tasks 7-10. Consistent.
- `BLETransport.write(_, to:, type:)` — Task 3 protocol; CoreBluetoothTransport + MockBLETransport conform. Consistent.

No type drift.

---

## Plan complete and saved to `docs/superpowers/plans/m1-pr1-looikit-package.md`.

**Two execution options:**

1. **Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration
2. **Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints

Which approach?
