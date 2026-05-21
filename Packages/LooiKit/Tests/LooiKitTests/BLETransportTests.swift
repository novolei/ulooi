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

    func test_radioState_allCases_distinct() {
        let states: [BLERadioState] = [.unknown, .unsupported, .unauthorized, .poweredOff, .poweredOn]
        // All pairwise comparisons where i != j should be unequal
        for i in states.indices {
            for j in states.indices where i != j {
                XCTAssertNotEqual(states[i], states[j])
            }
        }
    }

    func test_discoveredPeripheral_sameId_isEqual() {
        let id = UUID()
        let now = Date()
        let a = DiscoveredPeripheral(id: id, name: "LOOI", rssi: -60, advertisedServices: [], manufacturerData: nil, lastSeen: now)
        let b = DiscoveredPeripheral(id: id, name: "LOOI", rssi: -60, advertisedServices: [], manufacturerData: nil, lastSeen: now)
        XCTAssertEqual(a, b)
        // nonisolated hashValue — access directly to avoid autoclosure isolation issues
        let hashA = a.hashValue
        let hashB = b.hashValue
        XCTAssertEqual(hashA, hashB)
    }

    func test_discoveredPeripheral_differentId_isNotEqual() {
        let now = Date()
        let a = DiscoveredPeripheral(id: UUID(), name: "LOOI", rssi: -60, advertisedServices: [], manufacturerData: nil, lastSeen: now)
        let b = DiscoveredPeripheral(id: UUID(), name: "LOOI", rssi: -60, advertisedServices: [], manufacturerData: nil, lastSeen: now)
        XCTAssertNotEqual(a, b)
    }

    func test_discoveredPeripheral_usableAsSetElement() {
        let id = UUID()
        let now = Date()
        let p = DiscoveredPeripheral(id: id, name: "LOOI", rssi: -60, advertisedServices: [], manufacturerData: nil, lastSeen: now)
        var set: Set<DiscoveredPeripheral> = []
        set.insert(p)
        set.insert(p)
        XCTAssertEqual(set.count, 1)
    }

    func test_discoveredPeripheral_advertisedServices_storesStrings() {
        let uuid = CBUUID(string: "0000fed0-0000-1000-8000-00805f9b34fb")
        let p = DiscoveredPeripheral(
            id: UUID(),
            name: "LOOI",
            rssi: -55,
            advertisedServices: [uuid.uuidString],
            manufacturerData: nil,
            lastSeen: Date()
        )
        // Extract before XCTAssertEqual to avoid main actor-isolated property in autoclosure
        let first = p.advertisedServices.first
        XCTAssertEqual(first, uuid.uuidString)
    }

    func test_disconnectionReason_clean_isEqual() {
        XCTAssertEqual(DisconnectionReason.clean, DisconnectionReason.clean)
    }

    func test_disconnectionReason_errorCarriesString() {
        let r = DisconnectionReason.error("link lost")
        if case .error(let s) = r {
            XCTAssertEqual(s, "link lost")
        } else {
            XCTFail("Expected .error case")
        }
    }

    func test_disconnectionReason_differentErrors_notEqual() {
        XCTAssertNotEqual(DisconnectionReason.error("a"), DisconnectionReason.error("b"))
    }

    func test_disconnectionReason_cleanVsError_notEqual() {
        XCTAssertNotEqual(DisconnectionReason.clean, DisconnectionReason.error("x"))
    }
}
