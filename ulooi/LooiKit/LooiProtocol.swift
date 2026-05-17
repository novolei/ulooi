import CoreBluetooth
import Foundation

/// Looi BLE protocol constants synthesized from two reference repos:
///
/// - andrey-tut/LOOI-Robot — Python implementation, Layer 1 primitives, **verified working**
/// - splattydoesstuff/sooperchargeforbots — Android mod tooling, adds Layer 2 (FE00 17-byte)
///   + headlight (FED2) discovery
///
/// Two protocol layers exist; **M0.5/M1 use Layer 1 only**:
/// - **Layer 1** — primitive channels per system (motor / head / light / sensor / handshake).
///   Well documented, simple, cleanly maps to LooiKit's MotionController / LightController /
///   SensorStream abstraction.
/// - **Layer 2** — FE00 rich command channel using 17-byte packets that coordinate motor + LED
///   + screen animations. Discovered but incompletely reversed. Defer to M3+ if lipsync /
///   coordinated animations need it.
///
/// Verification status across this file:
/// - ✅  Verified by Python implementation (andrey-tut)
/// - ⚠️  Documented but unverified by us; assume firmware-version-dependent
/// - ❓  Reference exists but mechanism unclear
///
/// As M0.5 probe confirms (or refutes) entries, update the status comments and
/// record findings in docs/m0-5-prototype-findings.md.
enum LooiProtocol {

    // MARK: - Discovery

    /// Advertising name prefix used by Looi robots.
    /// ✅ Per andrey-tut's bleak scan filter.
    static let advertisedNamePrefix = "LOOI"

    // MARK: - Service / characteristic UUIDs

    /// All Looi-related characteristic UUIDs in one place.
    /// Note: BLE 16-bit UUIDs (`fed0`) are expressed in full 128-bit form here for
    /// strict CoreBluetooth equality.
    enum Char {
        // Layer 1 — primitive channels
        static let movement   = CBUUID(string: "0000fed0-0000-1000-8000-00805f9b34fb") // write
        static let head       = CBUUID(string: "0000fed1-0000-1000-8000-00805f9b34fb") // write
        static let light      = CBUUID(string: "0000fed2-0000-1000-8000-00805f9b34fb") // write
        static let sensors    = CBUUID(string: "0000fed5-0000-1000-8000-00805f9b34fb") // notify
        static let battery    = CBUUID(string: "0000fed8-0000-1000-8000-00805f9b34fb") // read
        static let telemetry  = CBUUID(string: "0000fed9-0000-1000-8000-00805f9b34fb") // notify (cliff, TOF, battery stream)
        static let handshake  = CBUUID(string: "0000feda-0000-1000-8000-00805f9b34fb") // write

        // Layer 2 — rich commands
        static let richCommand = CBUUID(string: "0000fe00-0000-1000-8000-00805f9b34fb") // write, 17-byte
        static let motorBoost  = CBUUID(string: "0000ff02-0000-1000-8000-00805f9b34fb") // write, high-speed motor

        // GATT standard
        static let deviceInfoManufacturer = CBUUID(string: "00002a29-0000-1000-8000-00805f9b34fb") // read
    }

    /// Service UUIDs the robot advertises. Concrete values are discovered at runtime
    /// via service discovery; we don't filter by service on scan (Looi may use a
    /// custom proprietary service UUID we won't know until inspect).
    static let scanServiceFilter: [CBUUID]? = nil

    // MARK: - Init handshake

    /// REQUIRED before the robot responds to any command. Without this, motor / light writes
    /// silently no-op. Source: andrey-tut Python implementation, verified.
    ///
    /// Execute in order:
    /// 1. Optional GATT manufacturer read (macOS-only cache warmup; harmless on iOS)
    /// 2. Write `handshakePhase1Byte` to Char.handshake
    /// 3. Subscribe to Char.sensors AND Char.telemetry (set notify true)
    /// 4. Write `handshakePhase2Byte` to Char.handshake
    enum Handshake {
        static let phase1Byte: UInt8 = 0x01
        static let phase2Byte: UInt8 = 0x03

        static let phase1Data: Data = Data([phase1Byte])
        static let phase2Data: Data = Data([phase2Byte])

        /// Ordered list of (label, characteristic, data) write steps for the user-facing
        /// CommandView. Subscriptions are not in here — do them between writes (see UX).
        static let writeSteps: [(label: String, characteristic: CBUUID, data: Data)] = [
            ("handshake 1/2 — 0x01", Char.handshake, phase1Data),
            ("handshake 2/2 — 0x03", Char.handshake, phase2Data),
        ]
    }

    // MARK: - Timing

    enum Timing {
        /// Movement commands must be sent at least this often or the motors disengage.
        /// ✅ Source: andrey-tut "Heartbeat required every ~30ms".
        static let motorHeartbeatInterval: Duration = .milliseconds(30)

        /// Battery read polling interval used by andrey-tut.
        static let batteryPollInterval: Duration = .seconds(4)

        /// Typical end-to-end BLE write round-trip on iOS (rough; M0.5 probe will measure exact).
        static let bleWriteRTTEstimate: Duration = .milliseconds(30)
    }
}
