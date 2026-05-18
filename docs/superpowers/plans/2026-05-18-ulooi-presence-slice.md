# ulooi M1.2 Presence Slice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the approved M1.2 "Presence Slice: 它醒了" so connected landscape becomes Looi Face Mode and portrait/disconnected becomes Standalone App Mode, with face/light/head/motion responding together to touch, wave, look-at-me, sleep, and suspended safety.

**Architecture:** Keep physical BLE control inside `Packages/LooiKit`; add only the reusable physical gesture actor there. Put product presence, mode selection, face rendering, and app shell in the `ulooi` app target. Preserve existing DevTools under Settings/Developer and do not touch the separate `/Users/ryanliu/Documents/uclaw` git repo.

**Tech Stack:** Swift 6.x, SwiftUI, Observation, CoreBluetooth through existing `LooiKit`, XCTest through `LooiKitTests`, Xcode iOS simulator build.

---

## File Structure

Create or modify these files:

- Modify: `Packages/LooiKit/Sources/LooiKit/Controllers/SensorController.swift` — make M0.5 FED9/FED8 semantics explicit enough for Presence safety.
- Create: `Packages/LooiKit/Tests/LooiKitTests/Fixtures/FED9Samples.swift` — replay samples from `docs/m0-5-prototype-findings.md`.
- Modify: `Packages/LooiKit/Tests/LooiKitTests/SensorControllerTests.swift` — add replay tests before changing decoder behavior.
- Create: `Packages/LooiKit/Sources/LooiKit/Gestures/GestureKind.swift` — shared gesture identifiers.
- Create: `Packages/LooiKit/Sources/LooiKit/Gestures/GestureLibrary.swift` — three high-quality physical gestures: wave, lookAtMe, sleep.
- Create: `Packages/LooiKit/Tests/LooiKitTests/GestureLibraryTests.swift` — mock-BLE tests for sequencing, cleanup, and cliff blocking.
- Create: `ulooi/Main/ModeController.swift` — maps onboarding/session/orientation/developer intent to top-level surface.
- Create: `ulooi/Main/Presence/PresenceState.swift` — app-level state derived from LooiSession and sensors.
- Create: `ulooi/Main/Presence/PresenceDirector.swift` — coordinates face state and calls `GestureLibrary`.
- Create: `ulooi/Main/Presence/FaceModel.swift` — expression/gaze/glow/copy model used by views.
- Create: `ulooi/Main/Face/GeometricFaceView.swift` — SwiftUI Canvas face renderer.
- Create: `ulooi/Main/EmbodiedHomeView.swift` — landscape face mode.
- Create: `ulooi/Main/StandaloneHomeView.swift` — portrait/disconnected normal app mode.
- Create: `ulooi/Onboarding/OnboardingView.swift` — minimal pairing/welcome path.
- Create: `ulooi/Settings/SettingsRootView.swift` — Settings with Developer entry to existing DevTools.
- Modify: `ulooi/ContentView.swift` — route ordinary users to production shell instead of DevTools.
- Create: `docs/m1-2-presence-smoke-test-checklist.md` — simulator and real-Looi smoke checklist.

Do not create UCLAW WebSocket/CBOR transport, ASR/TTS, long-term memory writeback, background BLE, or autonomous wandering in this plan.

---

### Task 1: Sensor Truth Replay Guardrails

**Files:**
- Create: `Packages/LooiKit/Tests/LooiKitTests/Fixtures/FED9Samples.swift`
- Modify: `Packages/LooiKit/Tests/LooiKitTests/SensorControllerTests.swift`
- Modify: `Packages/LooiKit/Sources/LooiKit/Controllers/SensorController.swift`

- [ ] **Step 1: Add replay fixtures from M0.5 findings**

Create `Packages/LooiKit/Tests/LooiKitTests/Fixtures/FED9Samples.swift`:

```swift
import Foundation

enum FED9Samples {
    static let bootComplete = Data([0x11, 0x01, 0x00])

    // M0.5: type 0x01 is 5 bytes: 0x01 followed by four binary contact states.
    // Observed grounded-like state.
    static let binarySensorsGrounded = Data([0x01, 0x01, 0x01, 0x01, 0x01])

    // M0.5: lifting Looi's front toggled byte 1 from 0x01 to 0x00.
    static let binarySensorsFrontLifted = Data([0x01, 0x00, 0x01, 0x01, 0x01])

    // M0.5: type 0x02 samples were observed as 3 bytes.
    static let imuLikeSample = Data([0x02, 0xFF, 0xF8])

    static let touchDown = Data([0x09, 0x01])
    static let touchUp = Data([0x09, 0x00])

    // Existing M1 decoder shape: type 0x01 as bitfield and type 0x02 as 3-axis LE.
    static let legacyBitfieldAllSuspended = Data([0x01, 0x0F])
    static let legacyIMU3Axis = Data([0x02, 0x01, 0x00, 0xFF, 0xFF, 0x00, 0x01])
}
```

- [ ] **Step 2: Write failing replay tests**

Append these tests to `SensorControllerTests`:

```swift
func test_m05BinarySensorGroundedAndFrontLiftedSamples_driveCliffState() async throws {
    let mock = MockBLETransport()
    let ctl = SensorController(transport: mock)

    let (sensorsStream, _) = AsyncStream<Data>.makeStream()
    let (telemetryStream, telemetryCont) = AsyncStream<Data>.makeStream()
    ctl.consume(sensors: sensorsStream, telemetry: telemetryStream)

    telemetryCont.yield(FED9Samples.binarySensorsGrounded)
    try await Task.sleep(for: .milliseconds(50))
    XCTAssertEqual(ctl.cliffState, .grounded)

    telemetryCont.yield(FED9Samples.binarySensorsFrontLifted)
    try await Task.sleep(for: .milliseconds(50))
    XCTAssertEqual(ctl.cliffState, .frontSuspended)

    telemetryCont.finish()
}

func test_m05ThreeByteIMUSample_isRetainedWithoutErasingLast3AxisIMU() async throws {
    let mock = MockBLETransport()
    let ctl = SensorController(transport: mock)

    let (sensorsStream, _) = AsyncStream<Data>.makeStream()
    let (telemetryStream, telemetryCont) = AsyncStream<Data>.makeStream()
    ctl.consume(sensors: sensorsStream, telemetry: telemetryStream)

    telemetryCont.yield(FED9Samples.legacyIMU3Axis)
    try await Task.sleep(for: .milliseconds(50))
    XCTAssertEqual(ctl.imu.x, 1)
    XCTAssertEqual(ctl.imu.y, -1)
    XCTAssertEqual(ctl.imu.z, 256)

    telemetryCont.yield(FED9Samples.imuLikeSample)
    try await Task.sleep(for: .milliseconds(50))
    XCTAssertEqual(ctl.lastMotionSampleRaw, FED9Samples.imuLikeSample)
    XCTAssertEqual(ctl.imu.x, 1)
    XCTAssertEqual(ctl.imu.y, -1)
    XCTAssertEqual(ctl.imu.z, 256)

    telemetryCont.finish()
}

func test_batteryPoll_readsFirstByteFromTwoByteFED8BatteryPacket() async throws {
    let mock = MockBLETransport()
    let ctl = SensorController(transport: mock)
    mock.stubRead(LooiProtocol.Char.battery, returns: Data([0x35, 0x00]))

    ctl.startBatteryPoll()
    try await Task.sleep(for: .milliseconds(100))

    XCTAssertEqual(ctl.batteryPercent, 53)
    ctl.cancelBatteryPoll()
}
```

- [ ] **Step 3: Run replay tests and verify they fail**

Run:

```bash
swift test --package-path Packages/LooiKit --filter SensorControllerTests
```

Expected: fails because `lastMotionSampleRaw` does not exist and current type `0x01` handling interprets byte 1 as a bitfield.

- [ ] **Step 4: Implement decoder changes**

Modify `SensorController.swift`:

```swift
public private(set) var lastMotionSampleRaw: Data? = nil
```

Replace `case 0x01` and `case 0x02` in `handleTelemetryPacket(_:)` with:

```swift
case 0x01:
    if data.count >= 5 {
        // M0.5 binary sensor packet: 0x01 [front] [rear?] [left?] [right?].
        // Confirmed: byte 1 == 0x00 when front is lifted, 0x01 when grounded.
        var state: CliffState = .grounded
        if data[1] == 0x00 { state.insert(.frontSuspended) }
        if data[2] == 0x00 { state.insert(.rearSuspended) }
        if data[3] == 0x00 { state.insert(.leftSuspended) }
        if data[4] == 0x00 { state.insert(.rightSuspended) }
        cliffState = state
    } else if data.count >= 2 {
        // Legacy one-byte bitfield retained for tests and future hardware variants.
        cliffState = CliffState(rawValue: data[1])
    } else {
        logger.warning("FED9 type 0x01: packet too short (\(data.count) bytes)")
    }

case 0x02:
    lastMotionSampleRaw = data
    guard data.count >= 7 else {
        logger.debug("FED9 type 0x02: retained short motion sample len=\(data.count, privacy: .public)")
        return
    }
    let x = data.readInt16LE(at: 1)
    let y = data.readInt16LE(at: 3)
    let z = data.readInt16LE(at: 5)
    imu = IMUReading(x: x, y: y, z: z)
    logger.debug("FED9 0x02: imu=(\(x),\(y),\(z))")
```

- [ ] **Step 5: Run tests and commit**

Run:

```bash
swift test --package-path Packages/LooiKit --filter SensorControllerTests
swift test --package-path Packages/LooiKit
```

Expected: all LooiKit tests pass.

Commit:

```bash
git add Packages/LooiKit/Sources/LooiKit/Controllers/SensorController.swift Packages/LooiKit/Tests/LooiKitTests/SensorControllerTests.swift Packages/LooiKit/Tests/LooiKitTests/Fixtures/FED9Samples.swift
git commit -m "test(sensor): replay M0.5 FED9 samples"
```

---

### Task 2: GestureLibrary v0 in LooiKit

**Files:**
- Create: `Packages/LooiKit/Sources/LooiKit/Gestures/GestureKind.swift`
- Create: `Packages/LooiKit/Sources/LooiKit/Gestures/GestureLibrary.swift`
- Create: `Packages/LooiKit/Tests/LooiKitTests/GestureLibraryTests.swift`

- [ ] **Step 1: Write failing tests for the three rituals**

Create `GestureLibraryTests.swift`:

```swift
import XCTest
@testable import LooiKit
import LooiKitTesting

@MainActor
final class GestureLibraryTests: XCTestCase {
    func test_sleep_stopsMotionDimsLightAndCentersHead() async throws {
        let mock = MockBLETransport()
        let motion = MotionController(transport: mock, cliffStateProvider: { .grounded })
        let head = HeadController(transport: mock)
        let light = LightController(transport: mock)
        let gestures = GestureLibrary(motion: motion, head: head, light: light)

        try motion.forward()
        try await gestures.perform(.sleep)

        XCTAssertEqual(motion.currentMotion, .stop)
        let writes = mock.writes
        XCTAssertTrue(writes.contains { $0.characteristicUUID == LooiProtocol.Char.light.uuidString && $0.data == Data([0x00]) })
        XCTAssertTrue(writes.contains { $0.characteristicUUID == LooiProtocol.Char.head.uuidString && $0.data == LooiCommand.Head.center })
    }

    func test_lookAtMe_centersHeadAndSetsWarmLight() async throws {
        let mock = MockBLETransport()
        let gestures = GestureLibrary(
            motion: MotionController(transport: mock, cliffStateProvider: { .grounded }),
            head: HeadController(transport: mock),
            light: LightController(transport: mock)
        )

        try await gestures.perform(.lookAtMe)

        let writes = mock.writes
        XCTAssertTrue(writes.contains { $0.characteristicUUID == LooiProtocol.Char.head.uuidString && $0.data == LooiCommand.Head.center })
        XCTAssertTrue(writes.contains { $0.characteristicUUID == LooiProtocol.Char.light.uuidString && $0.data.count == 1 && $0.data[0] >= 0x80 })
    }

    func test_wave_usesHeadLightAndReturnsToStop() async throws {
        let mock = MockBLETransport()
        let motion = MotionController(transport: mock, cliffStateProvider: { .grounded })
        let gestures = GestureLibrary(
            motion: motion,
            head: HeadController(transport: mock),
            light: LightController(transport: mock)
        )

        try await gestures.perform(.wave)

        XCTAssertEqual(motion.currentMotion, .stop)
        XCTAssertTrue(mock.writes.contains { $0.characteristicUUID == LooiProtocol.Char.head.uuidString })
        XCTAssertTrue(mock.writes.contains { $0.characteristicUUID == LooiProtocol.Char.light.uuidString })
    }

    func test_waveWhenSuspended_throwsAndDoesNotStartMotion() async {
        let mock = MockBLETransport()
        let motion = MotionController(transport: mock, cliffStateProvider: { .frontSuspended })
        let gestures = GestureLibrary(
            motion: motion,
            head: HeadController(transport: mock),
            light: LightController(transport: mock)
        )

        do {
            try await gestures.perform(.wave)
            XCTFail("Expected wave to throw cliffLocked when suspended")
        } catch LooiError.cliffLocked {
            XCTAssertEqual(motion.currentMotion, .stop)
        } catch {
            XCTFail("Expected cliffLocked, got \(error)")
        }
    }
}
```

- [ ] **Step 2: Run tests and verify missing types**

Run:

```bash
swift test --package-path Packages/LooiKit --filter GestureLibraryTests
```

Expected: compile failure for missing `GestureKind` and `GestureLibrary`.

- [ ] **Step 3: Add GestureKind**

Create `GestureKind.swift`:

```swift
import Foundation

public enum GestureKind: String, CaseIterable, Identifiable, Sendable {
    case wave
    case lookAtMe
    case sleep

    public var id: String { rawValue }
}
```

- [ ] **Step 4: Add GestureLibrary**

Create `GestureLibrary.swift`:

```swift
import Foundation

@MainActor
public final class GestureLibrary {
    private let motion: MotionController
    private let head: HeadController
    private let light: LightController

    public init(motion: MotionController, head: HeadController, light: LightController) {
        self.motion = motion
        self.head = head
        self.light = light
    }

    public func perform(_ kind: GestureKind) async throws {
        switch kind {
        case .wave:
            try await wave()
        case .lookAtMe:
            try await lookAtMe()
        case .sleep:
            try await sleep()
        }
    }

    public func wave() async throws {
        try motion.spinLeft(speed: 40)
        try await light.set(brightness: 0.85)
        try await head.lookUp()
        try await Task.sleep(for: .milliseconds(180))
        try motion.spinRight(speed: 40)
        try await light.set(brightness: 1.0)
        try await Task.sleep(for: .milliseconds(180))
        motion.stop()
        try await head.center()
        try await light.set(brightness: 0.45)
    }

    public func lookAtMe() async throws {
        motion.stop()
        try await head.center()
        try await light.set(brightness: 0.65)
    }

    public func sleep() async throws {
        motion.stop()
        try await head.center()
        try await light.off()
    }
}
```

- [ ] **Step 5: Run tests and commit**

Run:

```bash
swift test --package-path Packages/LooiKit --filter GestureLibraryTests
swift test --package-path Packages/LooiKit
```

Expected: all LooiKit tests pass.

Commit:

```bash
git add Packages/LooiKit/Sources/LooiKit/Gestures/GestureKind.swift Packages/LooiKit/Sources/LooiKit/Gestures/GestureLibrary.swift Packages/LooiKit/Tests/LooiKitTests/GestureLibraryTests.swift
git commit -m "feat(gestures): add three presence rituals"
```

---

### Task 3: App Presence Model and Mode Selection

**Files:**
- Create: `ulooi/Main/ModeController.swift`
- Create: `ulooi/Main/Presence/PresenceState.swift`
- Create: `ulooi/Main/Presence/FaceModel.swift`
- Create: `ulooi/Main/Presence/PresenceDirector.swift`

- [ ] **Step 1: Add top-level mode model**

Create `ModeController.swift`:

```swift
import Foundation
import LooiKit

enum UlooiSurface: Equatable {
    case onboarding
    case faceMode
    case standalone
    case developer
}

enum UlooiOrientation: Equatable {
    case portrait
    case landscape
}

@MainActor
@Observable
final class ModeController {
    var onboardingComplete: Bool
    var developerOpen = false

    init(onboardingComplete: Bool = UserDefaults.standard.bool(forKey: "ulooi.onboarding.complete")) {
        self.onboardingComplete = onboardingComplete
    }

    func completeOnboarding() {
        onboardingComplete = true
        UserDefaults.standard.set(true, forKey: "ulooi.onboarding.complete")
    }

    func resetOnboardingForTesting() {
        onboardingComplete = false
        UserDefaults.standard.set(false, forKey: "ulooi.onboarding.complete")
    }

    func surface(session: LooiSession, orientation: UlooiOrientation) -> UlooiSurface {
        if developerOpen { return .developer }
        if !onboardingComplete && session.pairedPeripheralID == nil { return .onboarding }
        if session.state == .ready && orientation == .landscape { return .faceMode }
        return .standalone
    }
}
```

- [ ] **Step 2: Add PresenceState**

Create `PresenceState.swift`:

```swift
import Foundation
import LooiKit

enum PresenceState: Equatable {
    case booting
    case lookingForBody
    case awake
    case idle
    case touched
    case performingGesture(GestureKind)
    case suspended
    case sleeping
    case disconnected
    case errorRecoverable(String)

    static func derive(sessionState: SessionState, cliffState: CliffState, lastTouchDate: Date?, now: Date, sleeping: Bool, activeGesture: GestureKind?) -> PresenceState {
        if let activeGesture { return .performingGesture(activeGesture) }
        if sleeping { return .sleeping }
        if cliffState.isSuspended { return .suspended }
        if let lastTouchDate, now.timeIntervalSince(lastTouchDate) < 1.2 { return .touched }
        switch sessionState {
        case .disconnected:
            return .disconnected
        case .scanning, .connecting, .discovering, .handshaking, .reconnecting:
            return .lookingForBody
        case .ready:
            return .idle
        }
    }
}
```

- [ ] **Step 3: Add face model**

Create `FaceModel.swift`:

```swift
import SwiftUI

enum FaceExpression: Equatable {
    case idle
    case happy
    case surprised
    case sleepy
    case cautious
    case looking
    case offline
}

enum FaceGaze: Equatable {
    case center
    case left
    case right
    case up
    case down
}

struct FaceModel {
    var expression: FaceExpression
    var gaze: FaceGaze
    var glow: Color
    var line: String

    static func from(_ state: PresenceState) -> FaceModel {
        switch state {
        case .booting, .lookingForBody:
            return FaceModel(expression: .looking, gaze: .center, glow: .cyan.opacity(0.65), line: "小身体在附近吗？")
        case .awake, .idle:
            return FaceModel(expression: .idle, gaze: .center, glow: .yellow.opacity(0.62), line: "我在。电量也还体面。")
        case .touched:
            return FaceModel(expression: .surprised, gaze: .up, glow: .mint.opacity(0.75), line: "欸，我醒着呢。")
        case .performingGesture(.wave):
            return FaceModel(expression: .happy, gaze: .center, glow: .orange.opacity(0.7), line: "小身体已就位。")
        case .performingGesture(.lookAtMe):
            return FaceModel(expression: .happy, gaze: .center, glow: .yellow.opacity(0.72), line: "看着你啦。")
        case .performingGesture(.sleep), .sleeping:
            return FaceModel(expression: .sleepy, gaze: .down, glow: .blue.opacity(0.45), line: "我先眯一下，有事轻轻叫我。")
        case .suspended:
            return FaceModel(expression: .cautious, gaze: .down, glow: .pink.opacity(0.65), line: "脚下突然很哲学。先别让我开车。")
        case .disconnected:
            return FaceModel(expression: .offline, gaze: .center, glow: .gray.opacity(0.55), line: "Looi 不在附近。")
        case .errorRecoverable(let message):
            return FaceModel(expression: .cautious, gaze: .center, glow: .red.opacity(0.55), line: message)
        }
    }
}
```

- [ ] **Step 4: Add PresenceDirector**

Create `PresenceDirector.swift`:

```swift
import Foundation
import LooiKit

@MainActor
@Observable
final class PresenceDirector {
    private let session: LooiSession
    private let gestures: GestureLibrary

    private(set) var activeGesture: GestureKind?
    private(set) var isSleeping = false
    private(set) var lastErrorLine: String?

    init(session: LooiSession) {
        self.session = session
        self.gestures = GestureLibrary(motion: session.motion, head: session.head, light: session.light)
    }

    var state: PresenceState {
        PresenceState.derive(
            sessionState: session.state,
            cliffState: session.sensor.cliffState,
            lastTouchDate: session.sensor.lastTouchEvent?.timestamp,
            now: Date(),
            sleeping: isSleeping,
            activeGesture: activeGesture
        )
    }

    var face: FaceModel {
        if let lastErrorLine {
            return FaceModel.from(.errorRecoverable(lastErrorLine))
        }
        return FaceModel.from(state)
    }

    func wake() {
        isSleeping = false
        lastErrorLine = nil
    }

    func perform(_ kind: GestureKind) {
        guard session.state == .ready else {
            lastErrorLine = "Looi 的小身体还没连上。"
            return
        }
        Task { @MainActor in
            activeGesture = kind
            lastErrorLine = nil
            do {
                try await gestures.perform(kind)
                isSleeping = (kind == .sleep)
            } catch LooiError.cliffLocked {
                lastErrorLine = "脚下需要支撑，先不乱动。"
            } catch {
                lastErrorLine = "刚刚没配合好，我缓一下。"
            }
            activeGesture = nil
        }
    }
}
```

- [ ] **Step 5: Build app**

Run:

```bash
xcodebuild build -project ulooi.xcodeproj -scheme ulooi -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -quiet
```

Expected: build succeeds.

Commit:

```bash
git add ulooi/Main/ModeController.swift ulooi/Main/Presence/PresenceState.swift ulooi/Main/Presence/FaceModel.swift ulooi/Main/Presence/PresenceDirector.swift
git commit -m "feat(presence): add mode and presence director"
```

---

### Task 4: Geometric Face Mode and Standalone App Mode

**Files:**
- Create: `ulooi/Main/Face/GeometricFaceView.swift`
- Create: `ulooi/Main/EmbodiedHomeView.swift`
- Create: `ulooi/Main/StandaloneHomeView.swift`

- [ ] **Step 1: Add geometric face renderer**

Create `GeometricFaceView.swift`:

```swift
import SwiftUI

struct GeometricFaceView: View {
    let model: FaceModel
    @State private var breath = false

    var body: some View {
        Canvas { context, size in
            let eyeWidth = size.width * 0.16
            let eyeHeight = eyeHeightForExpression(model.expression, size: size)
            let y = size.height * 0.44 + gazeOffset(model.gaze).height
            let leftX = size.width * 0.36 + gazeOffset(model.gaze).width
            let rightX = size.width * 0.64 + gazeOffset(model.gaze).width
            let eyeColor = eyeColorForExpression(model.expression)

            for x in [leftX, rightX] {
                let rect = CGRect(x: x - eyeWidth / 2, y: y - eyeHeight / 2, width: eyeWidth, height: eyeHeight)
                context.fill(Path(ellipseIn: rect), with: .color(eyeColor))
            }

            if model.expression == .happy {
                var smile = Path()
                smile.move(to: CGPoint(x: size.width * 0.43, y: size.height * 0.64))
                smile.addQuadCurve(to: CGPoint(x: size.width * 0.57, y: size.height * 0.64), control: CGPoint(x: size.width * 0.50, y: size.height * 0.70))
                context.stroke(smile, with: .color(.white.opacity(0.82)), lineWidth: 4)
            }
        }
        .background(
            RadialGradient(colors: [model.glow.opacity(breath ? 0.85 : 0.45), .black], center: .center, startRadius: 20, endRadius: 420)
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                breath.toggle()
            }
        }
    }

    private func eyeHeightForExpression(_ expression: FaceExpression, size: CGSize) -> CGFloat {
        switch expression {
        case .sleepy: return size.height * 0.035
        case .cautious: return size.height * 0.075
        case .surprised: return size.height * 0.19
        default: return size.height * 0.13
        }
    }

    private func eyeColorForExpression(_ expression: FaceExpression) -> Color {
        switch expression {
        case .offline: return .white.opacity(0.38)
        case .cautious: return .pink.opacity(0.9)
        case .sleepy: return .cyan.opacity(0.65)
        default: return .yellow
        }
    }

    private func gazeOffset(_ gaze: FaceGaze) -> CGSize {
        switch gaze {
        case .center: return .zero
        case .left: return CGSize(width: -18, height: 0)
        case .right: return CGSize(width: 18, height: 0)
        case .up: return CGSize(width: 0, height: -12)
        case .down: return CGSize(width: 0, height: 12)
        }
    }
}
```

- [ ] **Step 2: Add EmbodiedHomeView**

Create `EmbodiedHomeView.swift`:

```swift
import SwiftUI
import LooiKit

struct EmbodiedHomeView: View {
    @Bindable var director: PresenceDirector
    let openSettings: () -> Void

    var body: some View {
        ZStack {
            GeometricFaceView(model: director.face)
                .ignoresSafeArea()

            VStack {
                HStack {
                    statusPill
                    Spacer()
                    Button(action: openSettings) {
                        Image(systemName: "gearshape")
                    }
                    .buttonStyle(.bordered)
                    .tint(.white.opacity(0.2))
                }
                .padding(.horizontal, 24)
                .padding(.top, 18)

                Spacer()

                Text(director.face.line)
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.88))
                    .padding(.bottom, 12)

                HStack(spacing: 14) {
                    gestureButton(.wave, title: "招呼", systemImage: "hand.wave")
                    gestureButton(.lookAtMe, title: "看我", systemImage: "eye")
                    gestureButton(.sleep, title: "睡觉", systemImage: "moon")
                }
                .padding(.bottom, 26)
            }
        }
    }

    private var statusPill: some View {
        Text("Connected")
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(.black)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.yellow)
            .clipShape(Capsule())
    }

    private func gestureButton(_ kind: GestureKind, title: String, systemImage: String) -> some View {
        Button {
            director.perform(kind)
        } label: {
            Label(title, systemImage: systemImage)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .frame(width: 110, height: 48)
        }
        .buttonStyle(.borderedProminent)
        .tint(.white.opacity(0.16))
        .foregroundStyle(.white)
    }
}
```

- [ ] **Step 3: Add StandaloneHomeView**

Create `StandaloneHomeView.swift`:

```swift
import SwiftUI
import LooiKit

struct StandaloneHomeView: View {
    let session: LooiSession
    let director: PresenceDirector
    let openSettings: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("ulooi")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                    Text(director.face.line)
                        .font(.system(size: 18, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Label(statusText, systemImage: "dot.radiowaves.left.and.right")
                    Label(batteryText, systemImage: "battery.75")
                    Label("横屏连接 Looi 后会变成 Face Mode", systemImage: "iphone.landscape")
                }
                .font(.system(size: 16, weight: .medium, design: .rounded))

                Button {
                    director.wake()
                    session.startScanAndConnect()
                } label: {
                    Label("寻找 Looi", systemImage: "wave.3.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Spacer()
            }
            .padding(24)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: openSettings) {
                        Image(systemName: "gearshape")
                    }
                }
            }
        }
    }

    private var statusText: String {
        session.state == .ready ? "小身体已连接" : "Looi 不在附近，我会试着找它"
    }

    private var batteryText: String {
        if let battery = session.sensor.batteryPercent {
            return "上次电量 \(battery)%"
        }
        return "还没有电量读数"
    }
}
```

- [ ] **Step 4: Build app and commit**

Run:

```bash
xcodebuild build -project ulooi.xcodeproj -scheme ulooi -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -quiet
```

Expected: build succeeds.

Commit:

```bash
git add ulooi/Main/Face/GeometricFaceView.swift ulooi/Main/EmbodiedHomeView.swift ulooi/Main/StandaloneHomeView.swift
git commit -m "feat(ui): add face and standalone home modes"
```

---

### Task 5: Onboarding, Settings, and Root Routing

**Files:**
- Create: `ulooi/Onboarding/OnboardingView.swift`
- Create: `ulooi/Settings/SettingsRootView.swift`
- Modify: `ulooi/ContentView.swift`

- [ ] **Step 1: Add onboarding**

Create `OnboardingView.swift`:

```swift
import SwiftUI
import LooiKit

struct OnboardingView: View {
    let session: LooiSession
    let complete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Spacer()
            Text("给 Looi 一个小身体")
                .font(.system(size: 38, weight: .bold, design: .rounded))
            Text("连接后，手机会成为 Looi 的脸。带手机出门时，ulooi 仍是一个正常的陪伴 app。")
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            Button {
                session.startScanAndConnect()
                complete()
            } label: {
                Label("寻找附近的 Looi", systemImage: "wave.3.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Spacer()
        }
        .padding(28)
    }
}
```

- [ ] **Step 2: Add Settings with Developer entry**

Create `SettingsRootView.swift`:

```swift
import SwiftUI
import LooiKit

struct SettingsRootView: View {
    let session: LooiSession
    let openDeveloper: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("Looi") {
                    LabeledContent("Connection", value: session.state.description)
                    if let battery = session.sensor.batteryPercent {
                        LabeledContent("Battery", value: "\(battery)%")
                    }
                    Button("Forget pairing", role: .destructive) {
                        session.forgetPairing()
                    }
                }

                Section("Developer") {
                    Button {
                        openDeveloper()
                    } label: {
                        Label("Open DevTools", systemImage: "hammer")
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}
```

- [ ] **Step 3: Replace root DevTools routing**

Replace `ContentView.swift` with:

```swift
import SwiftUI
import LooiKit

struct ContentView: View {
    let session = LooiBootstrap.shared.session
    @State private var mode = ModeController()
    @State private var director = PresenceDirector(session: LooiBootstrap.shared.session)
    @State private var showingSettings = false

    var body: some View {
        GeometryReader { proxy in
            let orientation: UlooiOrientation = proxy.size.width > proxy.size.height ? .landscape : .portrait

            switch mode.surface(session: session, orientation: orientation) {
            case .onboarding:
                OnboardingView(session: session) {
                    mode.completeOnboarding()
                }
            case .faceMode:
                EmbodiedHomeView(director: director) {
                    showingSettings = true
                }
                .sheet(isPresented: $showingSettings) {
                    SettingsRootView(session: session) {
                        mode.developerOpen = true
                        showingSettings = false
                    }
                }
            case .standalone:
                StandaloneHomeView(session: session, director: director) {
                    showingSettings = true
                }
                .sheet(isPresented: $showingSettings) {
                    SettingsRootView(session: session) {
                        mode.developerOpen = true
                        showingSettings = false
                    }
                }
            case .developer:
                DevToolsRootView()
            }
        }
    }
}

#Preview {
    ContentView()
}
```

- [ ] **Step 4: Build app and commit**

Run:

```bash
xcodebuild build -project ulooi.xcodeproj -scheme ulooi -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -quiet
```

Expected: build succeeds and root no longer compiles directly to DevTools.

Commit:

```bash
git add ulooi/Onboarding/OnboardingView.swift ulooi/Settings/SettingsRootView.swift ulooi/ContentView.swift
git commit -m "feat(app): route dual-mode presence shell"
```

---

### Task 6: Visual Polish and Smoke Checklist

**Files:**
- Modify: `ulooi/Main/Face/GeometricFaceView.swift`
- Modify: `ulooi/Main/EmbodiedHomeView.swift`
- Modify: `ulooi/Main/StandaloneHomeView.swift`
- Create: `docs/m1-2-presence-smoke-test-checklist.md`

- [ ] **Step 1: Add the smoke checklist**

Create `docs/m1-2-presence-smoke-test-checklist.md`:

```markdown
# M1.2 Presence Slice Smoke Test Checklist

## Simulator

- [ ] Fresh install starts in onboarding when no pairing is stored.
- [ ] Tap "寻找附近的 Looi" starts scan and completes onboarding state.
- [ ] Portrait layout shows Standalone App Mode.
- [ ] Landscape layout with a ready session shows Looi Face Mode.
- [ ] Settings opens from both standalone and face modes.
- [ ] Settings -> Developer opens the existing DevTools tabs.

## Real Looi

- [ ] Pair/connect reaches `LooiSession.state == .ready`.
- [ ] Landscape shows large face, connected pill, and three actions.
- [ ] Touching Looi changes face line/expression and does not require DevTools.
- [ ] Wave runs head/light/motion then returns motion to stop.
- [ ] Look at me centers head and sets warm light.
- [ ] Sleep centers head, stops motion, and turns light off.
- [ ] Lifting the front makes motion unsafe and shows cautious safety copy.
- [ ] Walking away or disconnecting leaves a coherent Standalone App Mode.
```

- [ ] **Step 2: Run package tests**

Run:

```bash
swift test --package-path Packages/LooiKit
```

Expected: all tests pass.

- [ ] **Step 3: Build app**

Run:

```bash
xcodebuild build -project ulooi.xcodeproj -scheme ulooi -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -quiet
```

Expected: build succeeds.

- [ ] **Step 4: Manual simulator check**

Run:

```bash
xcrun simctl boot "iPhone 17" || true
open -a Simulator
xcodebuild build -project ulooi.xcodeproj -scheme ulooi -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -quiet
```

Expected: app builds for simulator. Launch from Xcode or Simulator to verify onboarding/standalone/settings. This plan does not require automated screenshot tooling before the first implementation pass.

- [ ] **Step 5: Commit**

Commit:

```bash
git add ulooi/Main/Face/GeometricFaceView.swift ulooi/Main/EmbodiedHomeView.swift ulooi/Main/StandaloneHomeView.swift docs/m1-2-presence-smoke-test-checklist.md
git commit -m "docs(smoke): add M1.2 presence checklist"
```

---

## Final Verification

Run:

```bash
swift test --package-path Packages/LooiKit
xcodebuild build -project ulooi.xcodeproj -scheme ulooi -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -quiet
git status --short
```

Expected:

- LooiKit tests pass.
- iOS simulator build succeeds.
- `git status --short` is clean except for pre-existing unrelated user/doc changes that were intentionally not part of this implementation.

## Execution Notes

- Keep commits scoped to the paths listed in each task.
- Do not revert existing README, PRD, architecture, or next-step plan edits unless Ryan explicitly asks.
- Do not edit `/Users/ryanliu/Documents/uclaw` while implementing this plan; it is a separate git repository from `/Users/ryanliu/Documents/uclaw/ulooi`.
- If real Looi hardware is unavailable, finish simulator/package verification and leave unchecked real-hardware checklist items in the final report.
