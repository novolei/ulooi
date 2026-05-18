import Foundation
import Observation
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
            defer { activeGesture = nil }

            do {
                try await gestures.perform(kind)
                isSleeping = (kind == .sleep)
            } catch LooiError.cliffLocked {
                lastErrorLine = "脚下需要支撑，先不乱动。"
            } catch {
                lastErrorLine = "刚刚没配合好，我缓一下。"
            }
        }
    }
}
