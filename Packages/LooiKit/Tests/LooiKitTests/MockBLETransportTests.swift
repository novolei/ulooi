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

        let writes = mock.writes
        XCTAssertEqual(writes.count, 2)
        // WriteCall stores characteristicUUID as String (uuidString) — Task 4 adaptation
        XCTAssertEqual(writes[0].characteristicUUID, c1.uuidString)
        XCTAssertEqual(writes[0].data, Data([0x01]))
        XCTAssertEqual(writes[0].type, .withoutResponse)
        XCTAssertEqual(writes[1].characteristicUUID, c2.uuidString)
        XCTAssertEqual(writes[1].data, Data([0x02, 0x03]))
        XCTAssertEqual(writes[1].type, .withResponse)
    }

    func test_write_emptyWritesInitially() {
        let mock = MockBLETransport()
        XCTAssertTrue(mock.writes.isEmpty)
    }

    func test_stubbedRead_returnsConfiguredData() async throws {
        let mock = MockBLETransport()
        mock.stubRead(LooiProtocol.Char.battery, returns: Data([0x55]))
        let value = try await mock.read(from: LooiProtocol.Char.battery)
        XCTAssertEqual(value, Data([0x55]))
    }

    func test_read_unstubbed_returnsEmptyData() async throws {
        let mock = MockBLETransport()
        let value = try await mock.read(from: LooiProtocol.Char.battery)
        XCTAssertEqual(value, Data())
    }

    func test_read_recordedInOrder() async throws {
        let mock = MockBLETransport()
        _ = try await mock.read(from: LooiProtocol.Char.battery)
        _ = try await mock.read(from: LooiProtocol.Char.telemetry)
        let reads = mock.reads
        // reads stores uuidString — Task 4 adaptation
        XCTAssertEqual(reads.count, 2)
        XCTAssertEqual(reads[0], LooiProtocol.Char.battery.uuidString)
        XCTAssertEqual(reads[1], LooiProtocol.Char.telemetry.uuidString)
    }

    func test_subscribe_recordedCharacteristic() async throws {
        let mock = MockBLETransport()
        _ = try await mock.subscribe(to: LooiProtocol.Char.telemetry)
        // subscriptions stores uuidString — Task 4 adaptation
        XCTAssertEqual(mock.subscriptions, [LooiProtocol.Char.telemetry.uuidString])
    }

    func test_subscribe_yieldsSimulatedNotifications() async throws {
        let mock = MockBLETransport()
        let stream = try await mock.subscribe(to: LooiProtocol.Char.telemetry)
        mock.simulateNotification(on: LooiProtocol.Char.telemetry, data: Data([0x09, 0x01]))
        mock.simulateNotification(on: LooiProtocol.Char.telemetry, data: Data([0x09, 0x02]))

        var received: [Data] = []
        var iter = stream.makeAsyncIterator()
        for _ in 0..<2 {
            if let v = await iter.next() { received.append(v) }
        }
        XCTAssertEqual(received, [Data([0x09, 0x01]), Data([0x09, 0x02])])
    }

    func test_queuedConnectionFailure_throwsLooiError() async {
        let mock = MockBLETransport()
        mock.queueFailure(.connectionFailure)
        do {
            try await mock.connect(UUID())
            XCTFail("expected throw")
        } catch let err as LooiError {
            if case .connectionFailed = err {
                // expected
            } else {
                XCTFail("expected LooiError.connectionFailed, got \(err)")
            }
        } catch {
            XCTFail("expected LooiError, got \(error)")
        }
    }

    func test_queuedCharacteristicMissing_throwsOnMatchingWrite() async {
        let mock = MockBLETransport()
        let char = LooiProtocol.Char.movement
        // Task 4 adaptation: Failure stores uuidString, not CBUUID
        mock.queueFailure(.characteristicMissing(char.uuidString))
        do {
            try await mock.write(Data([0x01]), to: char, type: .withoutResponse)
            XCTFail("expected throw")
        } catch let err as LooiError {
            if case .characteristicMissing(let uuidStr) = err {
                XCTAssertEqual(uuidStr, char.uuidString)
            } else {
                XCTFail("expected LooiError.characteristicMissing, got \(err)")
            }
        } catch {
            XCTFail("expected LooiError, got \(error)")
        }
    }

    func test_queuedWriteFailure_throwsOnMatchingWrite() async {
        let mock = MockBLETransport()
        let char = LooiProtocol.Char.head
        // Task 4 adaptation: Failure stores uuidString
        mock.queueFailure(.writeFailure(char.uuidString))
        do {
            try await mock.write(Data([0x02]), to: char, type: .withResponse)
            XCTFail("expected throw")
        } catch let err as LooiError {
            if case .writeFailed(let uuidStr, _) = err {
                XCTAssertEqual(uuidStr, char.uuidString)
            } else {
                XCTFail("expected LooiError.writeFailed, got \(err)")
            }
        } catch {
            XCTFail("expected LooiError, got \(error)")
        }
    }

    func test_failureDoesNotConsumeUnmatchedChar() async throws {
        let mock = MockBLETransport()
        let charA = LooiProtocol.Char.movement
        let charB = LooiProtocol.Char.head
        // Queue failure for charA, write to charB first — should succeed
        mock.queueFailure(.characteristicMissing(charA.uuidString))
        try await mock.write(Data([0x01]), to: charB, type: .withoutResponse)
        XCTAssertEqual(mock.writes.count, 1)
    }

    func test_radioState_defaultIsPoweredOn() async {
        let mock = MockBLETransport()
        let state = await mock.radioState
        XCTAssertEqual(state, .poweredOn)
    }

    func test_setRadioState_changesState() async {
        let mock = MockBLETransport()
        mock.setRadioState(.poweredOff)
        let state = await mock.radioState
        XCTAssertEqual(state, .poweredOff)
    }
}
