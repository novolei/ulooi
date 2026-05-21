import XCTest
import CoreBluetooth
@testable import LooiKit
import LooiKitTesting

/// SensorController unit tests.
///
/// All methods are @MainActor because SensorController is @MainActor —
/// XCTest cannot implicitly hop to @MainActor, so we declare the class
/// @MainActor explicitly (Swift 6 requirement).
///
/// Stream injection uses `AsyncStream<Data>.makeStream()` which returns
/// `(AsyncStream<Data>, AsyncStream<Data>.Continuation)`, letting tests
/// push data on demand without real BLE.
@MainActor
final class SensorControllerTests: XCTestCase {

    // MARK: - FED9 type 0x01 — cliff state

    func test_telemetryType0x01_decodesCliffState() async throws {
        let mock = MockBLETransport()
        let ctl = SensorController(transport: mock)

        let (sensorsStream, _) = AsyncStream<Data>.makeStream()
        let (telemetryStream, telemetryCont) = AsyncStream<Data>.makeStream()

        ctl.consume(sensors: sensorsStream, telemetry: telemetryStream)

        // 0x0F = bits 0b00001111 — all four cliff directions suspended
        telemetryCont.yield(Data([0x01, 0x0F]))

        // Give the consuming Task time to process one element.
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(ctl.cliffState, CliffState(rawValue: 0x0F),
                       "type 0x01 should set cliffState to the bitfield in byte 1")
        XCTAssertTrue(ctl.cliffState.contains(.frontSuspended))
        XCTAssertTrue(ctl.cliffState.contains(.rearSuspended))
        XCTAssertTrue(ctl.cliffState.contains(.leftSuspended))
        XCTAssertTrue(ctl.cliffState.contains(.rightSuspended))

        telemetryCont.finish()
    }

    // MARK: - FED9 type 0x02 — IMU

    func test_telemetryType0x02_decodesIMUSignedInt16LE() async throws {
        let mock = MockBLETransport()
        let ctl = SensorController(transport: mock)

        let (sensorsStream, _) = AsyncStream<Data>.makeStream()
        let (telemetryStream, telemetryCont) = AsyncStream<Data>.makeStream()

        ctl.consume(sensors: sensorsStream, telemetry: telemetryStream)

        // type=0x02, x=1 (0x01 0x00 LE), y=-1 (0xFF 0xFF LE), z=256 (0x00 0x01 LE)
        telemetryCont.yield(Data([0x02, 0x01, 0x00, 0xFF, 0xFF, 0x00, 0x01]))

        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(ctl.imu.x, 1,   "x should be 1 (LE 0x01 0x00)")
        XCTAssertEqual(ctl.imu.y, -1,  "y should be -1 (LE 0xFF 0xFF)")
        XCTAssertEqual(ctl.imu.z, 256, "z should be 256 (LE 0x00 0x01)")

        telemetryCont.finish()
    }

    // MARK: - FED9 type 0x09 — touch event

    func test_telemetryType0x09_updatesLastTouchEvent() async throws {
        let mock = MockBLETransport()
        let ctl = SensorController(transport: mock)

        let (sensorsStream, _) = AsyncStream<Data>.makeStream()
        let (telemetryStream, telemetryCont) = AsyncStream<Data>.makeStream()

        ctl.consume(sensors: sensorsStream, telemetry: telemetryStream)

        // Initial state: no touch event
        XCTAssertNil(ctl.lastTouchEvent)

        telemetryCont.yield(Data([0x09, 0x42]))

        try await Task.sleep(for: .milliseconds(50))

        XCTAssertNotNil(ctl.lastTouchEvent,
                        "type 0x09 should update lastTouchEvent")
        XCTAssertEqual(ctl.lastTouchEvent?.raw, 0x42,
                       "raw byte should match byte 1 of the packet")

        telemetryCont.finish()
    }

    // MARK: - FED9 type 0x11 — boot status (log-only)

    func test_telemetryType0x11_doesNotCrashOrUpdateOtherFields() async throws {
        let mock = MockBLETransport()
        let ctl = SensorController(transport: mock)

        let (sensorsStream, _) = AsyncStream<Data>.makeStream()
        let (telemetryStream, telemetryCont) = AsyncStream<Data>.makeStream()

        ctl.consume(sensors: sensorsStream, telemetry: telemetryStream)

        let beforeCliff = ctl.cliffState
        let beforeIMU   = ctl.imu

        // Boot status packet — should only log, not touch observable state
        telemetryCont.yield(Data([0x11, 0x01, 0x02]))

        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(ctl.cliffState, beforeCliff,
                       "type 0x11 must not modify cliffState")
        XCTAssertEqual(ctl.imu, beforeIMU,
                       "type 0x11 must not modify imu")
        XCTAssertNil(ctl.lastTouchEvent,
                     "type 0x11 must not modify lastTouchEvent")

        telemetryCont.finish()
    }

    // MARK: - Battery poll

    func test_batteryPoll_readsFED8AndUpdatesPercent() async throws {
        let mock = MockBLETransport()
        let ctl = SensorController(transport: mock)

        // FED8 returns 0x55 = 85
        mock.stubRead(LooiProtocol.Char.battery, returns: Data([0x55]))

        XCTAssertNil(ctl.batteryPercent, "batteryPercent should start nil")

        ctl.startBatteryPoll()

        // The poll fires immediately on Task start (read first, then sleep 4s).
        // 100ms is enough to capture the first read.
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(ctl.batteryPercent, 85,
                       "batteryPercent should be 85 (0x55)")
        XCTAssertGreaterThanOrEqual(ctl.batteryPollCount, 1,
                                    "at least one battery read should have completed")

        let batteryUUID = LooiProtocol.Char.battery.uuidString
        let batteryReads = mock.reads.filter { $0 == batteryUUID }
        XCTAssertGreaterThanOrEqual(batteryReads.count, 1,
                                    "mock should have recorded at least one FED8 read")

        ctl.cancelBatteryPoll()
    }

    func test_cancelBatteryPoll_stopsReads() async throws {
        let mock = MockBLETransport()
        let ctl = SensorController(transport: mock)
        mock.stubRead(LooiProtocol.Char.battery, returns: Data([0x64]))

        ctl.startBatteryPoll()

        // Let the poll fire at least once (fires immediately, then sleeps 4s).
        try await Task.sleep(for: .milliseconds(100))
        let countAfterStart = ctl.batteryPollCount
        XCTAssertGreaterThanOrEqual(countAfterStart, 1,
                                    "should have polled at least once before cancel")

        // Cancel; the 4s sleep means a second read won't arrive for a long time.
        ctl.cancelBatteryPoll()

        // Wait 200ms — well within the 4s poll interval — and verify no new reads.
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(ctl.batteryPollCount, countAfterStart,
                       "battery poll count must not grow after cancelBatteryPoll")
    }

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
}
