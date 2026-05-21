import Foundation
@preconcurrency import CoreBluetooth
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

    public nonisolated init(transport: BLETransport) {
        self.transport = transport
    }

    public struct SubscribedStreams: Sendable {
        public let sensors: AsyncStream<Data>
        public let telemetry: AsyncStream<Data>
    }

    /// Run the full sequence. Throws `LooiError.handshakeFailed(step:)`
    /// on any per-step failure.
    public nonisolated func run() async throws -> SubscribedStreams {
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
