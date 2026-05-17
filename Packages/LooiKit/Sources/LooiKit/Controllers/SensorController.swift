import Foundation
import Observation
import OSLog

/// Decodes FED5 (sensors) and FED9 (telemetry) notification streams and
/// exposes the results as @Observable properties.
///
/// Lifecycle invariants (driven by LooiSession):
/// - I3: LooiSession enters .ready  → `startBatteryPoll()` called
/// - I4: LooiSession leaves .ready  → `cancelBatteryPoll()` + `stopConsuming()` called
///
/// Swift 6 notes:
/// - @MainActor by package default (`defaultIsolation(MainActor.self)`).
/// - Task properties use `@ObservationIgnored nonisolated(unsafe)` so deinit
///   can call `.cancel()` without a MainActor hop. All writes happen on @MainActor.
/// - Stream-consuming Tasks are spawned with `Task { @MainActor [weak self] in … }`
///   so `handleSensorPacket` / `handleTelemetryPacket` always run on @MainActor.
@MainActor
@Observable
public final class SensorController {

    // MARK: - Nested types

    /// Raw IMU reading decoded from FED9 type 0x02 packets.
    /// Three signed 16-bit little-endian values at byte offsets 1, 3, 5.
    public struct IMUReading: Sendable, Equatable {
        public let x: Int16
        public let y: Int16
        public let z: Int16

        public static let zero = IMUReading(x: 0, y: 0, z: 0)

        public init(x: Int16, y: Int16, z: Int16) {
            self.x = x
            self.y = y
            self.z = z
        }
    }

    /// Touch event decoded from FED9 type 0x09 packets (or FED5 raw packets).
    public struct TouchEvent: Sendable, Equatable {
        public let raw: UInt8
        public let timestamp: Date

        public init(raw: UInt8, timestamp: Date = Date()) {
            self.raw = raw
            self.timestamp = timestamp
        }
    }

    // MARK: - Observable state

    public private(set) var cliffState: CliffState = .grounded
    public private(set) var imu: IMUReading = .zero
    public private(set) var batteryPercent: Int? = nil
    public private(set) var lastTouchEvent: TouchEvent? = nil

    /// Number of completed battery poll reads. Exposed for testing.
    public private(set) var batteryPollCount: Int = 0

    // MARK: - Dependencies

    private let transport: BLETransport
    private let logger = Logger(subsystem: "ai.if2.ulooi", category: "looikit.sensor")

    // MARK: - Task handles
    // @ObservationIgnored prevents @Observable macro from wrapping these in
    // @ObservationTracked (which conflicts with nonisolated(unsafe)).
    // nonisolated(unsafe) allows deinit to cancel without a MainActor hop.
    // All writes happen on @MainActor.
    @ObservationIgnored nonisolated(unsafe) private var batteryTask: Task<Void, Never>?
    @ObservationIgnored nonisolated(unsafe) private var sensorsTask: Task<Void, Never>?
    @ObservationIgnored nonisolated(unsafe) private var telemetryTask: Task<Void, Never>?

    // MARK: - Init

    public init(transport: BLETransport) {
        self.transport = transport
    }

    deinit {
        batteryTask?.cancel()
        sensorsTask?.cancel()
        telemetryTask?.cancel()
    }

    // MARK: - Stream consumption

    /// Hook up the two notification streams returned by HandshakeRunner.
    ///
    /// Spawns two Tasks that forward each element to the appropriate
    /// packet handler. Safe to call once per connection — calling again
    /// cancels prior tasks and restarts.
    public func consume(sensors: AsyncStream<Data>, telemetry: AsyncStream<Data>) {
        // Cancel any prior stream tasks before rebinding.
        sensorsTask?.cancel()
        telemetryTask?.cancel()

        sensorsTask = Task { @MainActor [weak self] in
            for await data in sensors {
                guard !Task.isCancelled else { break }
                self?.handleSensorPacket(data)
            }
        }

        telemetryTask = Task { @MainActor [weak self] in
            for await data in telemetry {
                guard !Task.isCancelled else { break }
                self?.handleTelemetryPacket(data)
            }
        }
    }

    /// Cancel stream-consuming tasks. Called by LooiSession on .ready exit (I4).
    public func stopConsuming() {
        sensorsTask?.cancel()
        sensorsTask = nil
        telemetryTask?.cancel()
        telemetryTask = nil
    }

    // MARK: - Battery poll (I3 / I4)

    /// Begin reading FED8 every `LooiProtocol.Timing.batteryPollInterval` (4s).
    ///
    /// Safe to call repeatedly — cancels any prior battery task first.
    /// Called by LooiSession when entering .ready (I3).
    public func startBatteryPoll() {
        cancelBatteryPoll()
        batteryPollCount = 0
        batteryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            self.logger.info("battery poll: starting (4s interval)")
            while !Task.isCancelled {
                do {
                    let data = try await self.transport.read(from: LooiProtocol.Char.battery)
                    // Single byte: value is percent (0–100). andrey-tut reads raw and
                    // interprets as percentage directly.
                    if let byte = data.first {
                        self.batteryPercent = Int(byte)
                    }
                    self.batteryPollCount += 1
                    self.logger.debug("battery poll \(self.batteryPollCount): \(String(describing: self.batteryPercent), privacy: .public)%")
                } catch {
                    self.logger.warning("battery poll: read failed: \(String(describing: error), privacy: .public)")
                }
                try? await Task.sleep(for: LooiProtocol.Timing.batteryPollInterval)
            }
            self.logger.info("battery poll: stopped after \(self.batteryPollCount) reads")
        }
    }

    /// Cancel the battery poll task. Called by LooiSession on .ready exit (I4).
    public func cancelBatteryPoll() {
        batteryTask?.cancel()
        batteryTask = nil
    }

    // MARK: - Packet decoders

    /// Handle FED5 (sensor notification) packets.
    /// Currently records raw bytes as a TouchEvent. Full decoding TBD in M2.
    private func handleSensorPacket(_ data: Data) {
        guard let byte = data.first else { return }
        lastTouchEvent = TouchEvent(raw: byte, timestamp: Date())
    }

    /// Handle FED9 (telemetry) packets. Packet format:
    ///   byte 0: type
    ///   0x01 → cliff bitfield (byte 1)
    ///   0x02 → IMU 3× int16 LE (bytes 1-2, 3-4, 5-6)
    ///   0x09 → touch event raw (byte 1)
    ///   0x11 → boot status (log only)
    private func handleTelemetryPacket(_ data: Data) {
        guard !data.isEmpty else { return }
        let type = data[0]

        switch type {
        case 0x01:
            // Cliff state bitfield
            guard data.count >= 2 else {
                logger.warning("FED9 type 0x01: packet too short (\(data.count) bytes)")
                return
            }
            cliffState = CliffState(rawValue: data[1])
            logger.debug("FED9 0x01: cliffState=\(self.cliffState.rawValue, privacy: .public)")

        case 0x02:
            // IMU: 3× signed int16 little-endian at offsets 1, 3, 5
            guard data.count >= 7 else {
                logger.warning("FED9 type 0x02: packet too short (\(data.count) bytes)")
                return
            }
            let x = data.readInt16LE(at: 1)
            let y = data.readInt16LE(at: 3)
            let z = data.readInt16LE(at: 5)
            imu = IMUReading(x: x, y: y, z: z)
            logger.debug("FED9 0x02: imu=(\(x),\(y),\(z))")

        case 0x09:
            // Touch event raw byte
            guard data.count >= 2 else {
                logger.warning("FED9 type 0x09: packet too short (\(data.count) bytes)")
                return
            }
            lastTouchEvent = TouchEvent(raw: data[1], timestamp: Date())
            logger.debug("FED9 0x09: touchEvent raw=\(data[1], privacy: .public)")

        case 0x11:
            // Boot status — log only, no state update
            logger.info("FED9 0x11: boot status packet (len=\(data.count, privacy: .public))")

        default:
            logger.debug("FED9 unknown type 0x\(String(type, radix: 16), privacy: .public) (len=\(data.count, privacy: .public))")
        }
    }
}

// MARK: - Data helpers

/// Reads a signed 16-bit little-endian integer from `Data` at the given byte offset.
/// Caller must ensure `offset + 1 < data.count`.
fileprivate extension Data {
    func readInt16LE(at offset: Int) -> Int16 {
        let lo = UInt16(self[offset])
        let hi = UInt16(self[offset + 1])
        return Int16(bitPattern: lo | (hi << 8))
    }
}
