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
    }
}
