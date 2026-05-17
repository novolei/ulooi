import Foundation
import LooiKit

/// App-level singleton holding the production LooiSession.
///
/// Stores both the transport and session at the same level so DevTools can
/// independently drive `transport.scan(...)` via `DevToolsScanCoordinator`
/// while the session drives the production connect/handshake/heartbeat pipeline.
///
/// Until M1 PR 3 reshapes the app to inject LooiSession via @Environment,
/// DevTools and future production UI both reach the session via .shared.
@MainActor
public final class LooiBootstrap {
    public static let shared = LooiBootstrap()

    /// The underlying BLE transport — exposed so DevToolsScanCoordinator can
    /// drive independent scan streams without going through LooiSession's
    /// auto-connect flow.
    public let transport: BLETransport

    /// The production session that owns the full connect/handshake/heartbeat
    /// pipeline and all four controllers.
    public let session: LooiSession

    private init() {
        let cbt = CoreBluetoothTransport()
        self.transport = cbt
        self.session = LooiSession(transport: cbt)

        // Cold-launch auto-reconnect: poll transport.radioState until BLE is
        // powered on (typically <1s after CBCentralManager init); if a paired
        // peripheral is on record from a prior successful session, kick off
        // the connect pipeline. Matches M0.5's BLECentral.centralManagerDidUpdateState
        // auto-reconnect behavior — without this, every app launch requires
        // the user to manually Scan + Connect again.
        Task { @MainActor [session = self.session, transport = cbt] in
            for _ in 0..<30 {  // up to ~30s waiting for radio
                let radio = await transport.radioState
                if radio == .poweredOn {
                    if let pairedID = session.pairedPeripheralID {
                        DevLog.event(
                            "auto-reconnect: BLE powered on, attempting paired \(pairedID.uuidString.prefix(8))",
                            channel: DevLog.ble
                        )
                        session.connect(to: pairedID)
                    } else {
                        DevLog.event(
                            "auto-reconnect: BLE powered on but no paired peripheral on record",
                            channel: DevLog.ble
                        )
                    }
                    return
                }
                try? await Task.sleep(for: .seconds(1))
            }
            DevLog.warn(
                "auto-reconnect: BLE radio never reached poweredOn within 30s — giving up",
                channel: DevLog.ble
            )
        }
    }
}
