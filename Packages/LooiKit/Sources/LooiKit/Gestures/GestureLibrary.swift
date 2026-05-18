import Foundation

@MainActor
public final class GestureLibrary {
    private let motion: MotionController
    private let head: HeadController
    private let light: LightController

    public init(motion: MotionController, head: HeadController, light: LightController) {
        self.motion = motion
        self.head = head
        self.light = light
    }

    public func perform(_ kind: GestureKind) async throws {
        switch kind {
        case .wave:
            try await wave()
        case .lookAtMe:
            try await lookAtMe()
        case .sleep:
            try await sleep()
        }
    }

    public func wave() async throws {
        do {
            try motion.spinLeft(speed: 40)
            try await light.set(brightness: 0.85)
            try await head.lookUp()
            try await Task.sleep(for: .milliseconds(180))
            try motion.spinRight(speed: 40)
            try await light.set(brightness: 1.0)
            try await Task.sleep(for: .milliseconds(180))
            try await restoreAwakePose()
        } catch is CancellationError {
            try? await restoreAwakePose()
            throw CancellationError()
        } catch LooiError.cliffLocked(let directions) {
            motion.stop()
            throw LooiError.cliffLocked(directions: directions)
        } catch {
            try? await restoreAwakePose()
            throw error
        }
    }

    public func lookAtMe() async throws {
        motion.stop()
        try await head.center()
        try await light.set(brightness: 0.65)
    }

    public func sleep() async throws {
        motion.stop()
        try await head.center()
        try await light.off()
    }

    private func restoreAwakePose() async throws {
        motion.stop()
        try await head.center()
        try await light.set(brightness: 0.45)
    }
}
