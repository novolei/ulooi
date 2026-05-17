import XCTest
import CoreBluetooth
@testable import LooiKit
import LooiKitTesting

/// LooiSession lifecycle tests. All methods are @MainActor because LooiSession
/// is @MainActor — XCTest cannot implicitly hop to @MainActor, so we declare
/// the test class @MainActor explicitly (Swift 6 requirement).
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
        // Give the spawned Task time to transition .disconnected → .scanning.
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(session.state, .scanning)
    }

    func test_happyPath_endsInReady() async {
        let mock = MockBLETransport()
        // stubRead is nonisolated — no await needed.
        mock.stubRead(LooiProtocol.Char.deviceInfoManufacturer, returns: Data("LOOI".utf8))
        let session = LooiSession(transport: mock)

        session.startScanAndConnect(nameFilter: "LOOI")
        // Wait until scan task is running and waiting for discoveries.
        try? await Task.sleep(for: .milliseconds(50))

        // simulateDiscovery is nonisolated — no await needed.
        mock.simulateDiscovery(DiscoveredPeripheral(
            id: UUID(),
            name: "LOOI-1",
            rssi: -50,
            advertisedServices: [],
            manufacturerData: nil,
            lastSeen: Date()
        ))

        // HandshakeRunner has ~400ms of Task.sleep internally (100ms + 300ms).
        // Pad to 800ms for CI headroom.
        try? await Task.sleep(for: .milliseconds(800))
        XCTAssertEqual(session.state, .ready)
    }

    func test_disconnect_returnsToDisconnected() async {
        let mock = MockBLETransport()
        let session = LooiSession(transport: mock)
        session.disconnect()
        // Give the spawned Task time to execute.
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(session.state, .disconnected)
    }
}
