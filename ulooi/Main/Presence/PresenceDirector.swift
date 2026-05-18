import Foundation
import Observation
import LooiKit

@MainActor
@Observable
final class PresenceDirector {
    private let session: LooiSession
    private let gestures: GestureLibrary
    private static let bodyNotConnectedLine = "Looi 的小身体还没连上。"

    @ObservationIgnored private var gestureTask: Task<Void, Never>?
    @ObservationIgnored private var gestureGeneration = 0

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
        if session.state == .ready && lastErrorLine == Self.bodyNotConnectedLine {
            return FaceModel.from(state)
        }

        if let lastErrorLine {
            return FaceModel.from(.errorRecoverable(lastErrorLine))
        }
        return FaceModel.from(state)
    }

    func wake() {
        isSleeping = false
        lastErrorLine = nil
    }

    func reconcileSessionState() {
        guard session.state != .ready else {
            if lastErrorLine == Self.bodyNotConnectedLine {
                lastErrorLine = nil
            }
            return
        }

        gestureGeneration += 1
        gestureTask?.cancel()
        gestureTask = nil
        session.motion.stop()
        activeGesture = nil
        isSleeping = false
        lastErrorLine = nil
    }

    func perform(_ kind: GestureKind) {
        reconcileSessionState()

        guard activeGesture == nil, gestureTask == nil else {
            return
        }

        guard session.state == .ready else {
            lastErrorLine = Self.bodyNotConnectedLine
            return
        }

        gestureGeneration += 1
        let generation = gestureGeneration
        activeGesture = kind
        lastErrorLine = nil

        gestureTask = Task { @MainActor in
            guard generation == gestureGeneration else { return }

            defer {
                if generation == gestureGeneration {
                    activeGesture = nil
                    gestureTask = nil
                }
            }

            do {
                try await gestures.perform(kind)
                guard generation == gestureGeneration else { return }
                isSleeping = (kind == .sleep)
            } catch is CancellationError {
                return
            } catch LooiError.cliffLocked {
                guard generation == gestureGeneration else { return }
                lastErrorLine = "脚下需要支撑，先不乱动。"
            } catch {
                guard generation == gestureGeneration else { return }
                lastErrorLine = "刚刚没配合好，我缓一下。"
            }
        }
    }
}
